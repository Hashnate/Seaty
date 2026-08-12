const fs = require('fs');
const path = require('path');

const src = "C:\\Users\\afham\\.gemini\\antigravity-ide\\brain\\9dc27b16-05b8-462f-a46e-41b9b3552141\\media__1786504946397.jpg";
const dst = path.join(__dirname, "assets", "images", "colombo_to_kandy.jpg");

fs.copyFile(src, dst, (err) => {
  if (err) {
    console.error("Error copying file:", err);
  } else {
    console.log("Copied successfully!");
  }
});
