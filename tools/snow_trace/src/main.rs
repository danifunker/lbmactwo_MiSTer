use std::env;
use std::fs::{self, File};
use std::io::{BufWriter, Write};

use anyhow::Result;
use snow_core::cpu_m68k::cpu::HistoryEntry;
use snow_core::emulator::comm::{EmulatorCommand, EmulatorEvent, EmulatorSpeed};
use snow_core::emulator::Emulator;
use snow_core::mac::{ExtraROMs, MacModel};
use snow_core::tickable::Tickable;

fn main() -> Result<()> {
    env_logger::Builder::from_default_env()
        .filter_level(log::LevelFilter::Info)
        .init();

    let args: Vec<String> = env::args().collect();
    if args.len() < 4 {
        eprintln!("usage: snow_trace <rom> <display_rom> <cycles> [out.log]");
        std::process::exit(2);
    }
    let rom_path = &args[1];
    let display_rom_path = &args[2];
    let cycles: u64 = args[3].parse()?;
    let out_path = args
        .get(4)
        .cloned()
        .unwrap_or_else(|| "snow_trace.log".to_string());

    let rom = fs::read(rom_path)?;
    let display_rom = fs::read(display_rom_path)?;
    let model = MacModel::MacII;
    eprintln!("Forced model: {:?}", model);

    let extra = vec![ExtraROMs::MDC12(&display_rom)];
    let (mut emulator, _frame_recv) = Emulator::new(&rom, &extra, model)?;
    let cmd = emulator.create_cmd_sender();
    let event_recv = emulator.create_event_recv();

    cmd.send(EmulatorCommand::SetInstructionHistory(true))?;
    cmd.send(EmulatorCommand::Run)?;
    cmd.send(EmulatorCommand::SetSpeed(EmulatorSpeed::Uncapped))?;

    let mut out = BufWriter::new(File::create(&out_path)?);
    let mut count: u64 = 0;
    let mut last_pc: u32 = 0;
    let mut last_progress: u64 = 0;

    let mut last_drain_cycles: u64 = 0;
    while emulator.get_cycles() < cycles {
        emulator.tick(10000)?;
        // Force periodic history drain via Stop/Run cycle (Stop calls status_update)
        if emulator.get_cycles() - last_drain_cycles > 50000 {
            last_drain_cycles = emulator.get_cycles();
            cmd.send(EmulatorCommand::Stop)?;
            emulator.tick(1)?;
            cmd.send(EmulatorCommand::Run)?;
            emulator.tick(1)?;
        }
        let cur = emulator.get_cycles();
        if cur - last_progress > 2_000_000 {
            last_progress = cur;
            eprintln!("[snow] cyc={} PC={:08X} insns_logged={}", cur, last_pc, count);
            out.flush()?;
        }

        while let Ok(event) = event_recv.try_recv() {
            if let EmulatorEvent::InstructionHistory(hist) = event {
                for h in hist {
                    match h {
                        HistoryEntry::Instruction(i) => {
                            let raw_hex: String = i
                                .raw
                                .iter()
                                .map(|b| format!("{:02x}", b))
                                .collect::<Vec<_>>()
                                .join("");
                            writeln!(
                                out,
                                "PC={:08X} cyc={} raw={}",
                                i.pc, i.cycles, raw_hex
                            )?;
                            count += 1;
                            last_pc = i.pc as u32;
                        }
                        HistoryEntry::Exception { vector, cycles } => {
                            writeln!(out, "EXC vector={:08X} cyc={}", vector, cycles)?;
                        }
                        HistoryEntry::Pagefault { address, write } => {
                            writeln!(out, "PF addr={:08X} write={}", address, write)?;
                        }
                    }
                }
            }
        }
    }

    out.flush()?;
    eprintln!("Wrote {} entries to {}", count, out_path);
    Ok(())
}
