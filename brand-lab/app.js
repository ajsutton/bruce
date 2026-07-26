const directionButtons = [...document.querySelectorAll("[data-direction]")];
const panels = [...document.querySelectorAll("[data-panel]")];
const compareButton = document.querySelector("[data-compare]");
const nameCards = [...document.querySelectorAll("[data-name]")];
const spokenName = document.querySelector("[data-spoken-name]");
const speakButton = document.querySelector("[data-speak]");
const bruceModeButton = document.querySelector("[data-bruce-mode]");
const bruceModeLabel = document.querySelector("[data-mode-label]");
const bruceModeKey = "bruce-brand-mode";

function updateFavicon(fullBruce) {
  const canvas = document.createElement("canvas");
  canvas.width = 64;
  canvas.height = 64;
  const context = canvas.getContext("2d");
  context.fillStyle = fullBruce ? "#00563F" : "#EDE3D1";
  context.fillRect(0, 0, 64, 64);
  context.fillStyle = fullBruce ? "#FFCB18" : "#173E3B";
  context.font = fullBruce ? "900 47px system-ui" : "700 47px Georgia";
  context.fillText("B", 13, 49);
  context.fillStyle = "#D76548";
  context.beginPath();
  context.arc(49, 48, fullBruce ? 6 : 4, 0, Math.PI * 2);
  context.fill();

  let icon = document.querySelector('link[rel="icon"]');
  if (!icon) {
    icon = document.createElement("link");
    icon.rel = "icon";
    document.head.append(icon);
  }
  icon.href = canvas.toDataURL("image/png");
}

function setBruceMode(fullBruce, persist = true) {
  document.body.classList.toggle("full-bruce-active", fullBruce);
  bruceModeButton.setAttribute("aria-pressed", String(fullBruce));
  bruceModeLabel.textContent = fullBruce ? "Dial Bruce Back" : "Go The Full Bruce";
  updateFavicon(fullBruce);
  if (persist) localStorage.setItem(bruceModeKey, fullBruce ? "full" : "regular");
  showDirection(fullBruce ? "bruce-deluxe" : "bruce", false);
}

function showDirection(name, syncBruceMode = true) {
  document.body.classList.remove("compare-mode");
  compareButton.setAttribute("aria-pressed", "false");
  compareButton.classList.remove("active");

  directionButtons.forEach((button) => {
    button.classList.toggle("active", button.dataset.direction === name);
  });

  panels.forEach((panel) => {
    const active = panel.dataset.panel === name;
    panel.hidden = !active;
    panel.classList.toggle("active", active);
  });

  history.replaceState(null, "", `#${name}`);

  if (syncBruceMode && (name === "bruce" || name === "bruce-deluxe")) {
    const fullBruce = name === "bruce-deluxe";
    document.body.classList.toggle("full-bruce-active", fullBruce);
    bruceModeButton.setAttribute("aria-pressed", String(fullBruce));
    bruceModeLabel.textContent = fullBruce ? "Dial Bruce Back" : "Go The Full Bruce";
    updateFavicon(fullBruce);
  }
}

directionButtons.forEach((button) => {
  button.addEventListener("click", () => showDirection(button.dataset.direction));
});

compareButton.addEventListener("click", () => {
  const comparing = !document.body.classList.contains("compare-mode");
  document.body.classList.toggle("compare-mode", comparing);
  compareButton.setAttribute("aria-pressed", String(comparing));
  compareButton.classList.toggle("active", comparing);
  directionButtons.forEach((button) => button.classList.remove("active"));
  panels.forEach((panel) => {
    panel.hidden = false;
  });
  if (comparing) history.replaceState(null, "", "#compare");
  else setBruceMode(bruceModeButton.getAttribute("aria-pressed") === "true", false);
});

bruceModeButton.addEventListener("click", () => {
  setBruceMode(bruceModeButton.getAttribute("aria-pressed") !== "true");
});

const requested = location.hash.slice(1);
if (requested === "compare") {
  compareButton.click();
} else if (panels.some((panel) => panel.dataset.panel === requested)) {
  showDirection(requested);
} else {
  setBruceMode(localStorage.getItem(bruceModeKey) === "full", false);
}

nameCards.forEach((card) => {
  card.addEventListener("click", () => {
    const name = card.dataset.name;
    nameCards.forEach((candidate) => candidate.classList.toggle("selected", candidate === card));
    spokenName.textContent = name;
    speakButton.dataset.speak = `Hey Siri, ask ${name} to cool the house.`;
    speakButton.setAttribute("aria-label", `Hear the test sentence for ${name}`);
  });
});

speakButton.addEventListener("click", () => {
  if (!("speechSynthesis" in window)) return;
  window.speechSynthesis.cancel();
  window.speechSynthesis.speak(new SpeechSynthesisUtterance(speakButton.dataset.speak));
});
