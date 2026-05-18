// snow_dump — boot a Mac II floppy in Snow headlessly, run N cycles,
// dump a memory range. Used to verify supervisor_bench boot blocks
// without a display.
//
// Usage: snow_dump <rom> <display_rom> <floppy> <cycles> <addr_hex> <len>

use std::env;
use std::fs;

use anyhow::Result;
use snow_core::emulator::Emulator;
use snow_core::emulator::comm::{EmulatorCommand, EmulatorEvent, EmulatorSpeed};
use snow_core::mac::{ExtraROMs, MacModel};
use snow_core::tickable::Tickable;

fn main() -> Result<()> {
    env_logger::Builder::from_default_env()
        .filter_level(log::LevelFilter::Info)
        .init();

    let args: Vec<String> = env::args().collect();
    if args.len() < 7 {
        eprintln!(
            "usage: snow_dump <rom> <display_rom> <floppy> <cycles> <addr_hex> <len>"
        );
        std::process::exit(2);
    }
    let rom_path = &args[1];
    let display_rom_path = &args[2];
    let floppy_path = &args[3];
    let cycles: u64 = args[4].parse()?;
    let dump_addr = u32::from_str_radix(args[5].trim_start_matches("0x"), 16)?;
    let dump_len: usize = args[6].parse()?;

    let rom = fs::read(rom_path)?;
    let display_rom = fs::read(display_rom_path)?;
    let model = MacModel::MacII;
    eprintln!("model={:?}, floppy={}, cycles={}", model, floppy_path, cycles);

    let extra = vec![ExtraROMs::MDC12(&display_rom)];
    let (mut emulator, frame_recv) = Emulator::new(&rom, &extra, model)?;
    let cmd = emulator.create_cmd_sender();
    let event_recv = emulator.create_event_recv();

    cmd.send(EmulatorCommand::InsertFloppy(
        0,
        floppy_path.clone(),
        false,
    ))?;
    // Arm writeback so disk writes hit the source file when we Stop.
    cmd.send(EmulatorCommand::SetFloppyWriteback(0, true))?;
    cmd.send(EmulatorCommand::Run)?;
    cmd.send(EmulatorCommand::SetSpeed(EmulatorSpeed::Uncapped))?;

    // Reconstruct RAM contents from Memory events. Memory events fire
    // when status_update is called — i.e. on Stop. So we run free, then
    // pulse Stop/Run every so often to flush dirty pages.
    let mut ram = vec![0u8; 16 * 1024 * 1024];
    let mut last_drain_cycles: u64 = 0;
    let mut last_progress: u64 = 0;
    let mut last_pc: u32 = 0;
    let mut last_sr: u16 = 0;
    let mut last_d: [u32; 8] = [0; 8];
    let mut last_a: [u32; 7] = [0; 7];

    let drain = |event_recv: &crossbeam_channel::Receiver<EmulatorEvent>,
                 ram: &mut [u8],
                 last_pc: &mut u32,
                 last_sr: &mut u16,
                 last_d: &mut [u32; 8],
                 last_a: &mut [u32; 7]| {
        while let Ok(event) = event_recv.try_recv() {
            match event {
                EmulatorEvent::Memory((addr, data, _)) => {
                    let a = addr as usize;
                    let end = a + data.len();
                    if end <= ram.len() {
                        ram[a..end].copy_from_slice(&data);
                    }
                }
                EmulatorEvent::Status(s) => {
                    *last_pc = s.regs.pc;
                    *last_sr = s.regs.sr.0;
                    *last_d = s.regs.d;
                    *last_a = s.regs.a;
                }
                _ => {}
            }
        }
    };

    let mut last_frame: Option<(usize, usize, Vec<u8>)> = None;

    while emulator.get_cycles() < cycles {
        emulator.tick(10000, ())?;
        if emulator.get_cycles() - last_drain_cycles > 200_000 {
            last_drain_cycles = emulator.get_cycles();
            cmd.send(EmulatorCommand::Stop)?;
            emulator.tick(1, ())?;
            cmd.send(EmulatorCommand::Run)?;
            emulator.tick(1, ())?;
        }
        // Capture latest framebuffer (replaces previous).
        if let Some(buf) = {
            let mut lock = frame_recv.lock().unwrap();
            lock.take()
        } {
            let w = buf.width();
            let h = buf.height();
            last_frame = Some((w as usize, h as usize, buf.into_inner()));
        }
        let cur = emulator.get_cycles();
        if cur - last_progress > 2_000_000 {
            last_progress = cur;
            eprintln!("[snow] cyc={}", cur);
        }
        drain(&event_recv, &mut ram, &mut last_pc, &mut last_sr, &mut last_d, &mut last_a);
    }

    cmd.send(EmulatorCommand::Stop)?;
    emulator.tick(1, ())?;
    // Eject triggers try_writeback → saves modified disk back to source file.
    cmd.send(EmulatorCommand::EjectFloppy(0))?;
    emulator.tick(1, ())?;
    if let Some(buf) = {
        let mut lock = frame_recv.lock().unwrap();
        lock.take()
    } {
        let w = buf.width();
        let h = buf.height();
        last_frame = Some((w as usize, h as usize, buf.into_inner()));
    }
    drain(&event_recv, &mut ram, &mut last_pc, &mut last_sr, &mut last_d, &mut last_a);

    // Save the last framebuffer as PNG so we can SEE what's on the Mac's screen.
    if let Some((w, h, pixels)) = last_frame {
        let png_path = format!("/tmp/snow_dump_screen.png");
        let file = std::fs::File::create(&png_path)?;
        let mut encoder = png::Encoder::new(std::io::BufWriter::new(file), w as u32, h as u32);
        encoder.set_color(png::ColorType::Rgba);
        encoder.set_depth(png::BitDepth::Eight);
        let mut writer = encoder.write_header()?;
        writer.write_image_data(&pixels)?;
        eprintln!("screen saved: {} ({}x{}, {} bytes)", png_path, w, h, pixels.len());
    } else {
        eprintln!("no framebuffer captured");
    }
    println!("--- CPU @ end of run ---");
    println!("PC = {:08X}  SR = {:04X}", last_pc, last_sr);
    for i in 0..8 {
        println!("D{} = {:08X}", i, last_d[i]);
    }
    for i in 0..7 {
        println!("A{} = {:08X}", i, last_a[i]);
    }

    let start = dump_addr as usize;
    let end = start + dump_len;
    if end > ram.len() {
        anyhow::bail!("dump range exceeds tracked RAM size {}", ram.len());
    }
    let slice = &ram[start..end];
    println!("--- dump {:08X}..{:08X} ---", dump_addr, dump_addr + dump_len as u32);
    for (i, chunk) in slice.chunks(16).enumerate() {
        let line_addr = dump_addr as usize + i * 16;
        let hex: String = chunk
            .iter()
            .map(|b| format!("{:02X}", b))
            .collect::<Vec<_>>()
            .join(" ");
        let ascii: String = chunk
            .iter()
            .map(|&b| if (0x20..=0x7E).contains(&b) { b as char } else { '.' })
            .collect();
        println!("{:08X}  {:<48}  {}", line_addr, hex, ascii);
    }
    Ok(())
}
