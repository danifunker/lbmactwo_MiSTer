logerror "MAME_RESET script_start pc=%08X\n",pc
temp0 = 0
temp1 = 0
temp2 = 0
temp3 = 0
temp4 = 0
temp5 = 0
temp6 = 0
temp7 = 0
temp8 = 0
temp9 = 0
temp10 = 0
temp11 = 0
temp12 = 0

bp 40800E96:maincpu,++temp0==1,{ logerror "MAME_RESET pc=%08X label=call_151c tick=%08X d0=%08X d1=%08X d2=%08X d5=%08X d7=%08X a0=%08X a1=%08X a2=%08X a3=%08X a4=%08X a7=%08X ret=%08X w017a=%04X b0c2f=%02X l030a=%08X\n",pc,d@16a,d0,d1,d2,d5,d7,a0,a1,a2,a3,a4,a7,d@a7,w@17a,b@c2f,d@030a ; g }
bp 4080151C:maincpu,++temp1==1,{ logerror "MAME_RESET pc=%08X label=enter_151c tick=%08X d0=%08X d1=%08X d2=%08X d5=%08X d7=%08X a0=%08X a1=%08X a2=%08X a3=%08X a4=%08X a7=%08X ret=%08X w017a=%04X b0c2f=%02X l030a=%08X\n",pc,d@16a,d0,d1,d2,d5,d7,a0,a1,a2,a3,a4,a7,d@a7,w@17a,b@c2f,d@030a ; g }
bp 4080155A:maincpu,++temp2==1,{ logerror "MAME_RESET pc=%08X label=xpram_78 tick=%08X d0=%08X d1=%08X d2=%08X d5=%08X d7=%08X a0=%08X a1=%08X a2=%08X a3=%08X a4=%08X a7=%08X ret=%08X w017a=%04X b0c2f=%02X l030a=%08X\n",pc,d@16a,d0,d1,d2,d5,d7,a0,a1,a2,a3,a4,a7,d@a7,w@17a,b@c2f,d@030a ; g }
bp 4080156E:maincpu,++temp3==1,{ logerror "MAME_RESET pc=%08X label=xpram_76 tick=%08X d0=%08X d1=%08X d2=%08X d5=%08X d7=%08X a0=%08X a1=%08X a2=%08X a3=%08X a4=%08X a7=%08X ret=%08X w017a=%04X b0c2f=%02X l030a=%08X\n",pc,d@16a,d0,d1,d2,d5,d7,a0,a1,a2,a3,a4,a7,d@a7,w@17a,b@c2f,d@030a ; g }
bp 408015EA:maincpu,++temp4==1,{ logerror "MAME_RESET pc=%08X label=after_pram tick=%08X d0=%08X d1=%08X d2=%08X d5=%08X d7=%08X a0=%08X a1=%08X a2=%08X a3=%08X a4=%08X a7=%08X ret=%08X w017a=%04X b0c2f=%02X l030a=%08X\n",pc,d@16a,d0,d1,d2,d5,d7,a0,a1,a2,a3,a4,a7,d@a7,w@17a,b@c2f,d@030a ; g }
bp 4080166C:maincpu,++temp5==1,{ logerror "MAME_RESET pc=%08X label=pre_decision tick=%08X d0=%08X d1=%08X d2=%08X d5=%08X d7=%08X a0=%08X a1=%08X a2=%08X a3=%08X a4=%08X a7=%08X ret=%08X w017a=%04X b0c2f=%02X l030a=%08X\n",pc,d@16a,d0,d1,d2,d5,d7,a0,a1,a2,a3,a4,a7,d@a7,w@17a,b@c2f,d@030a ; g }
bp 408016D6:maincpu,++temp6==1,{ logerror "MAME_RESET pc=%08X label=mask_setup tick=%08X d0=%08X d1=%08X d2=%08X d5=%08X d7=%08X a0=%08X a1=%08X a2=%08X a3=%08X a4=%08X a7=%08X ret=%08X w017a=%04X b0c2f=%02X l030a=%08X\n",pc,d@16a,d0,d1,d2,d5,d7,a0,a1,a2,a3,a4,a7,d@a7,w@17a,b@c2f,d@030a ; g }
bp 408016EE:maincpu,++temp7==1,{ logerror "MAME_RESET pc=%08X label=call_bootmask tick=%08X d0=%08X d1=%08X d2=%08X d5=%08X d7=%08X a0=%08X a1=%08X a2=%08X a3=%08X a4=%08X a7=%08X ret=%08X w017a=%04X b0c2f=%02X l030a=%08X\n",pc,d@16a,d0,d1,d2,d5,d7,a0,a1,a2,a3,a4,a7,d@a7,w@17a,b@c2f,d@030a ; g }
bp 40807AD4:maincpu,++temp8==1,{ logerror "MAME_RESET pc=%08X label=bootmask_entry tick=%08X d0=%08X d1=%08X d2=%08X d5=%08X d7=%08X a0=%08X a1=%08X a2=%08X a3=%08X a4=%08X a7=%08X ret=%08X w017a=%04X b0c2f=%02X l030a=%08X\n",pc,d@16a,d0,d1,d2,d5,d7,a0,a1,a2,a3,a4,a7,d@a7,w@17a,b@c2f,d@030a ; g }
bp 40807CA2:maincpu,++temp9==1,{ logerror "MAME_RESET pc=%08X label=bootmask_ret tick=%08X d0=%08X d1=%08X d2=%08X d5=%08X d7=%08X a0=%08X a1=%08X a2=%08X a3=%08X a4=%08X a7=%08X ret=%08X w017a=%04X b0c2f=%02X l030a=%08X\n",pc,d@16a,d0,d1,d2,d5,d7,a0,a1,a2,a3,a4,a7,d@a7,w@17a,b@c2f,d@030a ; g }
bp 408061F2:maincpu,++temp10==1,{ logerror "MAME_RESET pc=%08X label=no_media_idle tick=%08X d0=%08X d1=%08X d2=%08X d5=%08X d7=%08X a0=%08X a1=%08X a2=%08X a3=%08X a4=%08X a7=%08X ret=%08X w017a=%04X b0c2f=%02X l030a=%08X\n",pc,d@16a,d0,d1,d2,d5,d7,a0,a1,a2,a3,a4,a7,d@a7,w@17a,b@c2f,d@030a ; g }
bp 408268D8:maincpu,++temp11==1,{ logerror "MAME_RESET pc=%08X label=scsi_transition tick=%08X d0=%08X d1=%08X d2=%08X d5=%08X d7=%08X a0=%08X a1=%08X a2=%08X a3=%08X a4=%08X a7=%08X ret=%08X w017a=%04X b0c2f=%02X l030a=%08X\n",pc,d@16a,d0,d1,d2,d5,d7,a0,a1,a2,a3,a4,a7,d@a7,w@17a,b@c2f,d@030a ; g }
bp 40826916:maincpu,++temp12==1,{ logerror "MAME_RESET pc=%08X label=scsi_loop tick=%08X d0=%08X d1=%08X d2=%08X d5=%08X d7=%08X a0=%08X a1=%08X a2=%08X a3=%08X a4=%08X a7=%08X ret=%08X w017a=%04X b0c2f=%02X l030a=%08X\n",pc,d@16a,d0,d1,d2,d5,d7,a0,a1,a2,a3,a4,a7,d@a7,w@17a,b@c2f,d@030a ; g }
g
