const root = document.documentElement;

const themeKey = "labia-proposal-theme";
try {
	const saved = localStorage.getItem(themeKey);
	if (saved) root.dataset.theme = saved;
} catch {}

document.querySelector("[data-theme-toggle]").addEventListener("click", () => {
	const dark = root.dataset.theme
		? root.dataset.theme === "dark"
		: matchMedia("(prefers-color-scheme: dark)").matches;
	root.dataset.theme = dark ? "light" : "dark";
	try {
		localStorage.setItem(themeKey, root.dataset.theme);
	} catch {}
});

const welcome = document.querySelector("[data-welcome]");
const steps = [...welcome.querySelectorAll(".welcome-step")];
const bars = [...welcome.querySelectorAll(".progress i")];
const next = welcome.querySelector("[data-welcome-next]");
const back = welcome.querySelector("[data-welcome-back]");
let step = 0;

function showStep(index) {
	step = (index + steps.length) % steps.length;
	steps.forEach((el, i) => el.classList.toggle("on", i === step));
	bars.forEach((el, i) => el.classList.toggle("on", i <= step));
	next.textContent = step === steps.length - 1 ? "Empezar a dictar" : "Continuar";
	back.style.visibility = step === 0 ? "hidden" : "visible";
}

next.addEventListener("click", () => showStep(step + 1));
back.addEventListener("click", () => showStep(step - 1));
showStep(0);

const settings = document.querySelector("[data-settings]");
const title = settings.querySelector("[data-title]");

settings.querySelectorAll(".side-item").forEach((item) => {
	item.addEventListener("click", () => {
		settings.querySelectorAll(".side-item").forEach((el) => el.setAttribute("aria-selected", el === item));
		settings.querySelectorAll(".pane").forEach((pane) => pane.classList.toggle("on", pane.dataset.paneId === item.dataset.pane));
		title.textContent = item.textContent.replace(/\d+$/, "").trim();
	});
});

document.querySelectorAll(".switch").forEach((el) => {
	el.addEventListener("click", () => el.setAttribute("aria-checked", el.getAttribute("aria-checked") !== "true"));
});

document.querySelectorAll(".segmented").forEach((group) => {
	group.querySelectorAll("button").forEach((button) => {
		button.addEventListener("click", () => {
			group.querySelectorAll("button").forEach((el) => el.setAttribute("aria-pressed", el === button));
		});
	});
});
