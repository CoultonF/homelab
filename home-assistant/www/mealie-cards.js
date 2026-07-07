/*
 * Mealie cards for Home Assistant Lovelace.
 *
 * mealie-shopping-card — unchecked items from a Mealie todo entity as a big bulleted list.
 * mealie-week-card     — Mon–Sun of the current week with the planned dinner(s) per day.
 *
 * Deployed to /config/www/ on the HAOS NUC and registered as a Lovelace
 * module resource (/local/mealie-cards.js?v=N — bump N after redeploying).
 */
(() => {
  const ordinal = (n) => {
    const s = ["th", "st", "nd", "rd"];
    const v = n % 100;
    return n + (s[(v - 20) % 10] || s[v] || s[0]);
  };

  const esc = (s) =>
    String(s).replace(
      /[&<>"']/g,
      (c) =>
        ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])
    );

  // Local-date helpers (all-day Mealie events carry plain YYYY-MM-DD dates).
  const ymd = (d) =>
    `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(
      d.getDate()
    ).padStart(2, "0")}`;

  const isoLocal = (d) => {
    const off = -d.getTimezoneOffset();
    const sign = off >= 0 ? "+" : "-";
    const pad = (n) => String(Math.abs(n)).padStart(2, "0");
    return (
      `${ymd(d)}T${pad(d.getHours())}:${pad(d.getMinutes())}:00` +
      `${sign}${pad(Math.trunc(off / 60))}:${pad(off % 60)}`
    );
  };

  const BASE_CSS = `
    ha-card { padding: 20px 24px; }
    .title { font-size: 2rem; font-weight: 700; margin: 0 0 14px; }
    ul { margin: 6px 0 4px; padding-left: 1.3em; }
    li { font-size: 1.5rem; line-height: 1.55; margin: 6px 0; }
    .muted { color: var(--secondary-text-color); }
    .error { color: var(--error-color, #b71c1c); font-size: 1.1rem; }
  `;

  class MealieBaseCard extends HTMLElement {
    constructor() {
      super();
      this.attachShadow({ mode: "open" });
    }

    // Re-fetch only when the backing entity actually changes state.
    set hass(hass) {
      this._hass = hass;
      const st = hass.states[this._config.entity];
      const stamp = st ? `${st.last_updated}|${st.state}` : "missing";
      if (stamp !== this._stamp) {
        this._stamp = stamp;
        this._refresh();
      }
    }

    _renderShell(body) {
      this.shadowRoot.innerHTML = `
        <style>${BASE_CSS}${this.constructor.CSS || ""}</style>
        <ha-card>
          <h1 class="title">${esc(this._config.title)}</h1>
          ${body}
        </ha-card>`;
    }

    getCardSize() {
      return 6;
    }
  }

  /* ------------------------------------------------------------------ */

  class MealieShoppingCard extends MealieBaseCard {
    setConfig(config) {
      this._config = {
        entity: "todo.mealie_weekly",
        title: "Groceries to Buy",
        ...config,
      };
      this._stamp = null;
    }

    async _refresh() {
      if (!this._hass) return;
      let body;
      try {
        const res = await this._hass.callWS({
          type: "todo/item/list",
          entity_id: this._config.entity,
        });
        const items = (res.items || []).filter(
          (i) => i.status === "needs_action"
        );
        body = items.length
          ? `<ul>${items.map((i) => `<li>${esc(i.summary)}</li>`).join("")}</ul>`
          : `<p class="muted" style="font-size:1.5rem">Nothing to buy</p>`;
      } catch (e) {
        body = `<p class="error">Couldn't load ${esc(this._config.entity)}: ${esc(
          e.message || e
        )}</p>`;
      }
      this._renderShell(body);
    }

    static getStubConfig() {
      return { entity: "todo.mealie_weekly", title: "Groceries to Buy" };
    }
  }

  /* ------------------------------------------------------------------ */

  class MealieWeekCard extends MealieBaseCard {
    static CSS = `
      .day { padding: 10px 0 12px 12px; border-left: 4px solid transparent; }
      .day.past { opacity: 0.55; }
      .day.today { border-left-color: var(--primary-color); }
      .day-head { display: flex; justify-content: space-between; align-items: baseline; gap: 12px; }
      .day-name { font-size: 1.4rem; font-weight: 600; }
      .today .day-name { font-weight: 800; }
      .day-date { font-size: 1.15rem; color: var(--secondary-text-color); white-space: nowrap; }
      .day li { font-size: 1.4rem; }
      .none { font-size: 1.3rem; margin: 4px 0 0 6px; }
      .sep { border: none; border-top: 1px solid var(--divider-color); margin: 2px 0; }
    `;

    setConfig(config) {
      this._config = {
        entity: "calendar.mealie_dinner",
        title: "Meal Planner",
        ...config,
      };
      this._stamp = null;
    }

    connectedCallback() {
      // Catch Mealie plan edits and day/week rollover between entity updates.
      this._timer = setInterval(() => this._refresh(), 30 * 60 * 1000);
    }

    disconnectedCallback() {
      clearInterval(this._timer);
    }

    async _refresh() {
      if (!this._hass) return;
      const now = new Date();
      const monday = new Date(
        now.getFullYear(),
        now.getMonth(),
        now.getDate() - ((now.getDay() + 6) % 7)
      );
      const sundayEnd = new Date(
        monday.getFullYear(),
        monday.getMonth(),
        monday.getDate() + 6,
        23,
        59,
        59
      );

      let events;
      try {
        events = await this._hass.callApi(
          "GET",
          `calendars/${this._config.entity}?start=${encodeURIComponent(
            isoLocal(monday)
          )}&end=${encodeURIComponent(isoLocal(sundayEnd))}`
        );
      } catch (e) {
        this._renderShell(
          `<p class="error">Couldn't load ${esc(this._config.entity)}: ${esc(
            e.message || e
          )}</p>`
        );
        return;
      }

      const today = ymd(now);
      const days = [];
      for (let i = 0; i < 7; i++) {
        const d = new Date(
          monday.getFullYear(),
          monday.getMonth(),
          monday.getDate() + i
        );
        const key = ymd(d);
        const meals = events.filter((ev) => {
          if (ev.start?.date) {
            // All-day events: [start, end) may span several days.
            return key >= ev.start.date && key < (ev.end?.date || ev.start.date);
          }
          return (ev.start?.dateTime || "").startsWith(key);
        });
        const cls =
          key === today ? "today" : key < today ? "past" : "";
        days.push(`
          <div class="day ${cls}">
            <div class="day-head">
              <span class="day-name">${d.toLocaleDateString(undefined, {
                weekday: "long",
              })}</span>
              <span class="day-date">${d.toLocaleDateString(undefined, {
                month: "long",
              })} ${ordinal(d.getDate())}, ${d.getFullYear()}</span>
            </div>
            ${
              meals.length
                ? `<ul>${meals
                    .map((m) => `<li>${esc(m.summary)}</li>`)
                    .join("")}</ul>`
                : `<p class="muted none">&mdash;</p>`
            }
          </div>`);
      }
      this._renderShell(days.join(`<hr class="sep">`));
    }

    static getStubConfig() {
      return { entity: "calendar.mealie_dinner", title: "Meal Planner" };
    }

    getCardSize() {
      return 12;
    }
  }

  customElements.define("mealie-shopping-card", MealieShoppingCard);
  customElements.define("mealie-week-card", MealieWeekCard);

  window.customCards = window.customCards || [];
  window.customCards.push(
    {
      type: "mealie-shopping-card",
      name: "Mealie Shopping List",
      description: "Large-print list of unchecked Mealie shopping list items",
    },
    {
      type: "mealie-week-card",
      name: "Mealie Week Planner",
      description: "Mon–Sun dinner plan from the Mealie calendar",
    }
  );
})();
