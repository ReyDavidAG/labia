import argparse

p = argparse.ArgumentParser(prog="labia", description="Dictado en español con transcripción en tiempo real.")
p.add_argument("--simulate", metavar="WAV", help="pasa un WAV de 16 kHz mono como si fuera en vivo")
p.add_argument("--abrir", action="store_true", help="abre los ajustes (si Labia ya corre, los abre en esa)")
p.add_argument("--reiniciar", action="store_true", help=argparse.SUPPRESS)  # waits for the old copy to exit
args = p.parse_args()

if args.simulate:
    from . import simulate

    simulate.run(args.simulate)
else:
    from . import app

    app.run(open_settings=args.abrir, restarting=args.reiniciar)
