bp 408015EA,1,{ trace /tmp/macii_mame_wait.tr,0,noloop,{ tracelog "tick=%08X d0=%08X d1=%08X d5=%08X d7=%08X a0=%08X a2=%08X a3=%08X a4=%08X w017a=%04X b0c2f=%02X ",d@16a,d0,d1,d5,d7,a0,a2,a3,a4,w@17a,b@c2f } ; g }
bp 40801666,1,{ trace off,0 ; g }
g
