const preview = document.querySelector(".demo");
const workspaceButtons = [...preview.querySelectorAll("button[data-space]")];
const firstTitle = preview.querySelector("[data-first-title]");
const secondTitle = preview.querySelector("[data-second-title]");
const status = preview.querySelector("[data-demo-status]");

function showWorkspace(button) {
  const { space, first, second } = button.dataset;
  preview.dataset.space = space;
  firstTitle.textContent = first;
  secondTitle.textContent = second;
  status.textContent = `Workspace ${space} · ${first} and ${second}`;

  for (const workspace of workspaceButtons) {
    workspace.setAttribute("aria-pressed", String(workspace === button));
  }
}

for (const button of workspaceButtons) {
  button.disabled = false;
  button.addEventListener("click", () => showWorkspace(button));
}

const copyButton = document.querySelector(".copy");
const commands = document.querySelector("#install-commands");
const copyStatus = document.querySelector("[data-copy-status]");

if (navigator.clipboard) {
  copyButton.hidden = false;
  copyButton.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(commands.textContent);
      copyButton.textContent = "Copied";
      copyStatus.textContent = "Build commands copied.";
    } catch {
      copyButton.textContent = "Select and copy";
      copyStatus.textContent = "Clipboard unavailable. Select the commands to copy them.";
    }
  });
}
