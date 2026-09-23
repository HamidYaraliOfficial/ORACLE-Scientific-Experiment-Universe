/* ============================================================
   ORACLE Web UI — Resource Availability
   A small, real, fully user-driven scheduler widget: the person adds
   one or more compute resources / lab instruments / worker pools,
   each with an "opens at" / "closes at" time they type in themselves
   (nothing hard-coded). The widget then computes, live, whether each
   resource is currently open or closed and how long until its next
   status change — the kind of maintenance-window information the
   Compute Resource Manager and Distributed Scheduler need to know
   about worker/lab availability.
   ============================================================ */

const Availability = (() => {
  let resources = []; // { id, name, opensAt: "HH:MM", closesAt: "HH:MM" }
  let idCounter = 1;
  let tickHandle = null;

  function addResource(name, opensAt, closesAt) {
    resources.push({ id: idCounter++, name, opensAt, closesAt });
    render();
  }

  function removeResource(id) {
    resources = resources.filter(r => r.id !== id);
    render();
  }

  function parseHHMM(s) {
    const [h, m] = s.split(":").map(Number);
    return h * 60 + m;
  }

  /** Returns { open: bool, minutesToChange: number } for a resource,
      given the current wall-clock time. Handles ranges that cross
      midnight (e.g. opens 22:00, closes 06:00) correctly. */
  function computeStatus(resource, now) {
    const nowMin = now.getHours() * 60 + now.getMinutes() + now.getSeconds() / 60;
    const openMin = parseHHMM(resource.opensAt);
    const closeMin = parseHHMM(resource.closesAt);
    let open, minutesToChange;
    if (openMin === closeMin) {
      // Degenerate case: identical open/close time is treated as "always open".
      open = true; minutesToChange = 24 * 60;
    } else if (openMin < closeMin) {
      open = nowMin >= openMin && nowMin < closeMin;
      minutesToChange = open ? (closeMin - nowMin) : ((nowMin < openMin ? openMin : openMin + 1440) - nowMin);
    } else {
      // crosses midnight, e.g. 22:00 -> 06:00
      open = nowMin >= openMin || nowMin < closeMin;
      if (open) {
        minutesToChange = (nowMin >= openMin ? closeMin + 1440 : closeMin) - nowMin;
      } else {
        minutesToChange = openMin - nowMin;
      }
    }
    return { open, minutesToChange: Math.max(0, minutesToChange) };
  }

  function formatDuration(minutesFloat) {
    const totalSeconds = Math.round(minutesFloat * 60);
    const h = Math.floor(totalSeconds / 3600);
    const m = Math.floor((totalSeconds % 3600) / 60);
    const s = totalSeconds % 60;
    if (h > 0) return `${h}h ${m}m`;
    if (m > 0) return `${m}m ${s}s`;
    return `${s}s`;
  }

  function render() {
    const container = document.getElementById("availability-list");
    if (!container) return;
    if (resources.length === 0) {
      container.innerHTML = `<div class="empty-state">${I18n.t("no_resources")}</div>`;
      return;
    }
    const now = new Date();
    container.innerHTML = resources.map(r => {
      const st = computeStatus(r, now);
      return `<div class="list-row" data-resource-id="${r.id}">
        <span class="status-dot ${st.open ? "open" : "closed"}"></span>
        <div style="flex:1">
          <div style="font-weight:700">${escapeHtml(r.name)}</div>
          <div style="font-size:12px;color:var(--color-text-secondary)">
            <span class="ltr-num">${r.opensAt}–${r.closesAt}</span>
            &nbsp;·&nbsp;
            <span class="badge ${st.open ? "ok" : "err"}">${st.open ? I18n.t("status_open") : I18n.t("status_closed")}</span>
            &nbsp;·&nbsp;${I18n.t("next_change_in")}: <span class="ltr-num next-change">${formatDuration(st.minutesToChange)}</span>
          </div>
        </div>
        <button class="btn small danger" onclick="Availability.removeResource(${r.id})">${I18n.t("remove")}</button>
      </div>`;
    }).join("");
  }

  function escapeHtml(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }

  function startClock() {
    if (tickHandle) clearInterval(tickHandle);
    tickHandle = setInterval(() => {
      const now = new Date();
      document.querySelectorAll("#availability-list [data-resource-id]").forEach(el => {
        const id = Number(el.getAttribute("data-resource-id"));
        const r = resources.find(x => x.id === id);
        if (!r) return;
        const st = computeStatus(r, now);
        const dot = el.querySelector(".status-dot");
        const badge = el.querySelector(".badge");
        const change = el.querySelector(".next-change");
        dot.className = "status-dot " + (st.open ? "open" : "closed");
        badge.className = "badge " + (st.open ? "ok" : "err");
        badge.textContent = st.open ? I18n.t("status_open") : I18n.t("status_closed");
        change.textContent = formatDuration(st.minutesToChange);
      });
    }, 1000);
  }

  function getResources() { return resources.slice(); }

  return { addResource, removeResource, render, startClock, getResources };
})();
