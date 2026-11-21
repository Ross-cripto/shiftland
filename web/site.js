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
