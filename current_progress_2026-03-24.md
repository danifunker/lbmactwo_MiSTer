⏺ Now I can see the full progression:

  ┌──────────┬───────────┬──────────────────────┐
  │  Cycles  │    PC     │        Phase         │
  ├──────────┼───────────┼──────────────────────┤
  │ 10M      │ $408036FE │ ROM init             │
  ├──────────┼───────────┼──────────────────────┤
  │ 20-60M   │ $40805F3C │ PRAM read            │
  ├──────────┼───────────┼──────────────────────┤
  │ 70M      │ $40806DDE │ ADB polling          │
  ├──────────┼───────────┼──────────────────────┤
  │ 80M      │ $40826CAA │ Delay loop           │
  ├──────────┼───────────┼──────────────────────┤
  │ 90-180M  │ $40805F3C │ PRAM read again      │
  ├──────────┼───────────┼──────────────────────┤
  │ 190-250M │ $40802EEA │ Slot Manager — STUCK │
  └──────────┴───────────┴──────────────────────┘

  The boot is now stuck in the Slot Manager sResource parsing loop. It's processing NuBus slot ROM entries endlessly —
  reading type bytes, dispatching, and looping back without ever hitting the end-of-list marker.

  Let me investigate the NuBus ROM reading to see if the data is being read correctly.
