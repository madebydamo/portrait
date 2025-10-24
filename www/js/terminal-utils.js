// Utility methods for Terminal class

Terminal.prototype.clearTerminal = function() {
  this.output.innerHTML = "";
  setTimeout(() => {
    this.showPrompt();
  }, 100);
};