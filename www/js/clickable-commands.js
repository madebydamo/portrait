// Clickable commands methods for Terminal class
// Anchors with href="/commands/...." remain real links for crawlers;
// in the interactive terminal, clicks are intercepted and run as commands.

Terminal.prototype.setupClickableCommands = function () {
  document.addEventListener("click", (e) => {
    const el = e.target.closest(".clickable-command");
    if (!el) return;

    const command = el.getAttribute("data-command");
    if (!command) return;

    // Keep terminal UX: do not navigate away from the SPA-style shell
    e.preventDefault();
    this.executeClickableCommand(command);
  });
};
