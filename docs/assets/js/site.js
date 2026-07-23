async function loadUpdates() {
  const target = document.querySelector("[data-updates]");
  if (!target) return;

  try {
    const response = await fetch("./updates.json", { cache: "no-store" });
    if (!response.ok) throw new Error("updates unavailable");
    const data = await response.json();
    target.innerHTML = `
      <h3>${data.version} · ${data.date}</h3>
      <p><strong>${data.headline}</strong></p>
      <ul>${data.highlights.map((item) => `<li>${item}</li>`).join("")}</ul>
    `;
  } catch (_) {
    target.innerHTML = `
      <h3>Latest release</h3>
      <p>Download the latest TaskMaster Pro build from GitHub Releases.</p>
    `;
  }
}

loadUpdates();
