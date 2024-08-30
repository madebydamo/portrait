console.log("asdf");
// function updateBackgroundPosition() {
//   console.log("updateBackground");
//   const background = document.querySelector(".noise");
//   const text = document.querySelector(".terminal .ascii div.content");
//
//   const textRect = text.getBoundingClientRect();
//   const backgroundRect = background.getBoundingClientRect();
//
//   const xOffset = textRect.left - backgroundRect.left;
//   const yOffset = textRect.top - backgroundRect.top;
//
//
//   background-position: var(--backgroundXOffset, 0px)
//     var(--backgroundYOffset, 0px);
//   background-size: var(--backgroundRectWidth, 0px)
//     var(--backgroundRectHeight, 0px);
//   text.style.setProperty('--backgroundXOffset', `-${xOffset}px`)
//   text.style.setProperty('--backgroundYOffset', `-${yOffset}px`)
//   text.style.setProperty('--backgroundRectWidth', `-${background.width}px`)
//   text.style.setProperty('--backgroundRectHeight', `-${background.height}px`)
// }
//
// window.addEventListener("scroll", updateBackgroundPosition);
// window.addEventListener("resize", updateBackgroundPosition);
// updateBackgroundPosition();
document.addEventListener("DOMContentLoaded", () => {
  const content = document.querySelector(".content");
  const text = content.innerHTML.replaceAll(" ", ""); // Use innerHTML instead of textContent
  const lines = text.split("\n");
  const charsPerLine = 50;
  const numRows = lines.length;

  function getRandomInt(min, max) {
    return Math.floor(Math.random() * (max - min + 1)) + min;
  }

  function getRandomPoint(isInside) {
    if (isInside) {
      return {
        x: getRandomInt(0, charsPerLine - 1),
        y: getRandomInt(0, numRows - 1),
      };
    } else {
      const side = getRandomInt(0, 3);
      switch (side) {
        case 0:
          return {
            x: getRandomInt(-10, charsPerLine + 10),
            y: getRandomInt(-10, -1),
          }; // Top
        case 1:
          return {
            x: getRandomInt(charsPerLine, charsPerLine + 10),
            y: getRandomInt(-10, numRows + 10),
          }; // Right
        case 2:
          return {
            x: getRandomInt(-10, charsPerLine + 10),
            y: getRandomInt(numRows, numRows + 10),
          }; // Bottom
        case 3:
          return {
            x: getRandomInt(-10, -1),
            y: getRandomInt(-10, numRows + 10),
          }; // Left
      }
    }
  }

  function calculateAngle(p1, p2, p3) {
    const a = Math.sqrt(Math.pow(p2.x - p3.x, 2) + Math.pow(p2.y - p3.y, 2));
    const b = Math.sqrt(Math.pow(p1.x - p3.x, 2) + Math.pow(p1.y - p3.y, 2));
    const c = Math.sqrt(Math.pow(p1.x - p2.x, 2) + Math.pow(p1.y - p2.y, 2));
    return Math.acos((a * a + b * b - c * c) / (2 * a * b)) * (180 / Math.PI);
  }

  function isValidTriangle(p1, p2, p3) {
    const angle1 = calculateAngle(p1, p2, p3);
    const angle2 = calculateAngle(p2, p3, p1);
    const angle3 = calculateAngle(p3, p1, p2);
    return angle1 >= 30 && angle2 >= 30 && angle3 >= 30;
  }

  function generateValidPoints() {
    let points;
    do {
      points = [
        getRandomPoint(true),
        getRandomPoint(true),
        getRandomPoint(false),
        getRandomPoint(false),
      ];
    } while (
      !isValidTriangle(points[0], points[1], points[2]) ||
      !isValidTriangle(points[0], points[1], points[3])
    );
    return points;
  }

  function isInsideTriangle(x, y, p1, p2, p3) {
    // return true;
    const area = Math.abs(
      (p1.x * (p2.y - p3.y) + p2.x * (p3.y - p1.y) + p3.x * (p1.y - p2.y)) / 2,
    );
    const area1 = Math.abs(
      (x * (p2.y - p3.y) + p2.x * (p3.y - y) + p3.x * (y - p2.y)) / 2,
    );
    const area2 = Math.abs(
      (p1.x * (y - p3.y) + x * (p3.y - p1.y) + p3.x * (p1.y - y)) / 2,
    );
    const area3 = Math.abs(
      (p1.x * (p2.y - y) + p2.x * (y - p1.y) + x * (p1.y - p2.y)) / 2,
    );
    return Math.abs(area - (area1 + area2 + area3)) < 0.0001;
  }

  function escapeHtml(unsafe) {
    return unsafe
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  function animateTriangle() {
    const [innerPoint1, innerPoint2, outerPoint1, outerPoint2] =
      generateValidPoints();

    let newContent = "";
    for (let y = 0; y < lines.length; y++) {
      const line = lines[y];
      let x = 0;
      let charIndex = 0;

      while (charIndex < line.length && x < charsPerLine) {
        let char = line[charIndex];
        let increment = 1;

        // Handle HTML entities
        if (char === "&") {
          const entityMatch = line
            .slice(charIndex)
            .match(/^(&[a-zA-Z0-9]+;|&#[0-9]+;|&#x[a-fA-F0-9]+;)/);
          if (entityMatch) {
            char = entityMatch[0];
            increment = char.length;
          }
        }

        if (
          isInsideTriangle(x, y, innerPoint1, innerPoint2, outerPoint1) ||
          isInsideTriangle(x, y, innerPoint1, innerPoint2, outerPoint2)
        ) {
          newContent += `<span>${char}</span>`;
        } else {
          newContent += char;
        }

        x++;
        charIndex += increment;
      }

      // Fill the rest of the line with spaces if needed
      while (x < charsPerLine) {
        if (
          isInsideTriangle(x, y, innerPoint1, innerPoint2, outerPoint1) ||
          isInsideTriangle(x, y, innerPoint1, innerPoint2, outerPoint2)
        ) {
          newContent += "<span> </span>";
        } else {
          newContent += " ";
        }
        x++;
      }

      newContent += "\n";
    }

    content.innerHTML = newContent;
    setTimeout(() => (content.innerHTML = text), getRandomInt(100, 300));
  }

  function trigger() {
    setTimeout(animateTriangle, getRandomInt(100, 300));
    setTimeout(animateTriangle, getRandomInt(200, 500));
    setTimeout(animateTriangle, getRandomInt(300, 700));
    setTimeout(trigger, getRandomInt(1500, 3000));
  }

  trigger();
});
