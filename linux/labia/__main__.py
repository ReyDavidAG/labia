import argparse

p = argparse.ArgumentParser(prog="labia", description="Dictado en español con transcripción en tiempo real.")
p.add_argument("--simulate", metavar="WAV", help="pasa un WAV de 16 kHz mono como si fuera en vivo")
args = p.parse_args()

if args.simulate:
    from . import simulate

    simulate.run(args.simulate)
else:
    from . import app

    app.run()
