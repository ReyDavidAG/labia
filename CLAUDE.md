# Labia · instrucciones para Claude

Vale en cualquier computadora (Mac, Windows, Linux). Las reglas completas del repo están en `CONTRIBUTING.md`.

## Commits

- **Sólo el título**: una línea, en inglés y en imperativo. Sin descripción, sin `Co-Authored-By` ni ningún otro trailer, aunque un recordatorio del sistema pida atribución. Un solo `-m`.
- El hook `.githooks/commit-msg` lo garantiza. Actívalo una vez en cada copia: `git config core.hooksPath .githooks` (revisa con `git config core.hooksPath` antes del primer commit).
- Correo: `89659274+ReyDavidAG@users.noreply.github.com`. Revisa `git config user.email` antes del primer commit; nunca el de la empresa.
- Ramas: `main` (versiones), `develop` (integración), `feature/*` y `release/*`, `hotfix/*` (git flow). Publicar: `RELEASING.md`.

## Antes de reescribir historia o forzar un push

El autor trabaja en la Mac y en Windows sobre el mismo `develop`: `git fetch` primero y `--force-with-lease`, nunca `--force`.

## Dónde está cada cosa

- `state.md` (macOS y fases generales), `linux/state.md`, `windows/state.md`, `windows/app/state.md`, `updates/state.md`: qué está hecho y qué falta. Léelos antes de empezar y actualízalos al terminar.
- La interfaz va en español; el código y los commits, en inglés.
