// Utility methods for Terminal class

Terminal.prototype.clearTerminal = function () {
  this.output.innerHTML = "";
  setTimeout(() => {
    this.showPrompt();
  }, 100);
};

// Global utility function to convert ANSI escape codes to HTML
window.ansiToHtml = function (text) {
  if (!text) return text;

  // Escape HTML entities first
  text = text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");

  // Function to get RGB from 256-color index
  function get256Color(n) {
    n = parseInt(n);
    if (n < 16) {
      // Basic colors (simplified)
      const basic = [
        "white",
        "#ff6666",
        "#66ff66",
        "#ffff66",
        "#6666ff",
        "#ff66ff",
        "#66ffff",
        "white",
        "#cccccc",
        "#ff8888",
        "#88ff88",
        "#ffff88",
        "#8888ff",
        "#ff88ff",
        "#88ffff",
        "white",
      ];
      return basic[n] || "white";
    } else if (n < 232) {
      // 6x6x6 color cube
      const r = Math.min(255, Math.floor((n - 16) / 36) * 51 + 50);
      const g = Math.min(255, Math.floor(((n - 16) % 36) / 6) * 51 + 50);
      const b = Math.min(255, ((n - 16) % 6) * 51 + 25);
      return `rgb(${r}, ${g}, ${b})`;
    } else {
      // Grayscale
      const gray = Math.min(255, (n - 232) * 10 + 28);
      return `rgb(${gray}, ${gray}, ${gray})`;
    }
  }

  // 256-color foreground: \x1b[38;5;Nm
  text = "<span>" + text;
  text = text.replace(
    /\x1b\[38;5;(\d+)m/g,
    (match, n) => `</span><span style="color: ${get256Color(n)}">`,
  );

  // 256-color background: \x1b[48;5;Nm
  text = text.replace(
    /\x1b\[48;5;(\d+)m/g,
    (match, n) => `</span><span style="background-color: ${get256Color(n)}">`,
  );

  // Reset
  text = text.replace(
    /\x1b\[0m/g,
    '</span><span style="color: var(--text-color)">',
  );

  // Handle other resets or incomplete codes
  // Remove other control sequences
  text = text.replace(/[[?0-9;]*[hl]/g, "");
  text = text.replace(/[[?0-9;]*[hl]/g, ""); // Again for nested
  text = text.replace(/\x1b\[[0-9;]*m/g, ""); // Remove any remaining escape sequences
  text = text + "</span>";

  return text;
};
