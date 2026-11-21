const workspaces = {
  "1": {
    summary: "Editor and Terminal",
    windows: [
      { title: "Editor", kind: "editor", template: "demo-editor" },
      { title: "Terminal", kind: "terminal", template: "demo-terminal" }
    ]
  },
  "2": {
    summary: "Browser and Reference",
    windows: [
      { title: "Browser", kind: "browser", template: "demo-browser" },
      { title: "Reference", kind: "reference", template: "demo-reference" }
    ]
  },
  "3": {
    summary: "Notes and Calendar",
    windows: [
      { title: "Notes", kind: "notes", template: "demo-notes" },
      { title: "Calendar", kind: "calendar", template: "demo-calendar" }
    ]
  }
};

const preview = document.querySelector(".demo");
const controls = preview.querySelector(".demo-controls");
const workspaceButtons = [...controls.querySelectorAll("button[data-space]")];
const desktop = preview.querySelector("#demo-desktop");
const status = preview.querySelector("[data-demo-status]");
const windowTemplate = document.getElementById("demo-window");

function createWindow(details) {
  const windowPanel = windowTemplate.content.firstElementChild.cloneNode(true);
  windowPanel.dataset.kind = details.kind;
  windowPanel.querySelector("[data-window-title]").textContent = details.title;
  const contentTemplate = document.getElementById(details.template);
  windowPanel.querySelector(".window-content").append(contentTemplate.content.cloneNode(true));
  return windowPanel;
}

function selectWorkspace(button) {
  const space = button.dataset.space;
  const workspace = workspaces[space];
  const windows = workspace.windows.map(createWindow);

  desktop.replaceChildren(...windows);
  preview.dataset.space = space;
  status.textContent = `Workspace ${space} · ${workspace.summary}`;

  for (const workspaceButton of workspaceButtons) {
    workspaceButton.setAttribute("aria-pressed", String(workspaceButton === button));
  }
}

function destinationForKey(key, selectedIndex) {
  const lastIndex = workspaceButtons.length - 1;

  switch (key) {
    case "ArrowLeft":
      return selectedIndex === 0 ? lastIndex : selectedIndex - 1;
    case "ArrowRight":
      return selectedIndex === lastIndex ? 0 : selectedIndex + 1;
    case "Home":
      return 0;
    case "End":
      return lastIndex;
    default:
      return null;
  }
}

function hasKeyboardModifier(event) {
  return event.altKey || event.ctrlKey || event.metaKey || event.shiftKey;
}

function navigateWorkspaces(event) {
  if (hasKeyboardModifier(event)) return;
  const selectedIndex = workspaceButtons.indexOf(event.target);
  if (selectedIndex === -1) return;

  const destination = destinationForKey(event.key, selectedIndex);
  if (destination === null) return;

  event.preventDefault();
  const button = workspaceButtons[destination];
  selectWorkspace(button);
  button.focus();
}

for (const button of workspaceButtons) {
  button.disabled = false;
  button.addEventListener("click", () => selectWorkspace(button));
}

controls.addEventListener("keydown", navigateWorkspaces);
selectWorkspace(workspaceButtons[0]);
