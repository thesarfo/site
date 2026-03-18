/**
 * SKILLS TIMELINE
 * Loads data/skills.json and renders an interactive skill timeline.
 *
 * Usage:
 *   <div id="skills-timeline"></div>
 *   <script src="skills-timeline.js"></script>
 *
 * Or with a custom data path:
 *   <div id="skills-timeline" data-src="path/to/skills.json"></div>
 */

(function () {
  'use strict';

  /* ─── Helpers ─────────────────────────────────────────── */

  function badgeClass(status) {
    const map = { done: 'st-badge-done', now: 'st-badge-now', upcoming: 'st-badge-upcoming', goal: 'st-badge-goal' };
    return map[status] || 'st-badge-upcoming';
  }

  function badgeLabel(status) {
    const map = { done: 'Done', now: 'Now', upcoming: 'Upcoming', goal: 'Goal' };
    return map[status] || status;
  }

  function esc(str) {
    const d = document.createElement('div');
    d.textContent = str;
    return d.innerHTML;
  }

  /* ─── Render ──────────────────────────────────────────── */

  function renderMilestone(m) {
    return `
      <div class="st-milestone" data-status="${esc(m.status)}" data-id="${esc(m.id)}">
        <div class="st-dot"></div>
        <div class="st-card" role="button" aria-expanded="false" tabindex="0">
          <div class="st-card-top">
            <div class="st-card-left">
              <div class="st-card-date">${esc(m.date)}</div>
              <div class="st-card-title">${esc(m.title)}</div>
            </div>
            <div class="st-card-right">
              <span class="st-badge ${badgeClass(m.status)}">${badgeLabel(m.status)}</span>
              <span class="st-chevron" aria-hidden="true">▼</span>
            </div>
          </div>
          <div class="st-detail" aria-hidden="true">
            <div class="st-detail-inner">
              ${m.description ? `<p>${esc(m.description)}</p>` : ''}
              ${m.reflection ? `<p class="st-reflection">"${esc(m.reflection)}"</p>` : ''}
            </div>
          </div>
        </div>
      </div>`;
  }

  function renderPanel(skill, index) {
    const isActive = index === 0;
    const milestonesHTML = skill.milestones.map(renderMilestone).join('');

    return `
      <div class="st-panel ${isActive ? 'active' : ''}" data-skill="${esc(skill.id)}">

        <div class="st-skill-header">
          <div class="st-skill-badge">
            <span class="st-status-dot"></span>
            ${esc(skill.status === 'active' ? 'In progress' : skill.status)}
          </div>
          <h2 class="st-skill-title">${skill.emoji ? skill.emoji + ' ' : ''}<em>${esc(skill.skill)}</em></h2>
          <p class="st-skill-meta">
            Started ${esc(skill.started)}
            ${skill.goal ? ` · Goal: ${esc(skill.goal)}` : ''}
            · ${skill.milestones.length} milestone${skill.milestones.length !== 1 ? 's' : ''} logged
          </p>
        </div>

        <div class="st-progress-wrap">
          <div class="st-progress-meta">
            <span>Progress</span>
            <span>${skill.progress}%</span>
          </div>
          <div class="st-progress-track">
            <div class="st-progress-fill" data-progress="${skill.progress}" style="width: 0%"></div>
          </div>
        </div>

        <div class="st-timeline">
          ${milestonesHTML}
        </div>

      </div>`;
  }

  function renderTabs(skills) {
    return skills.map((s, i) => `
      <button class="st-tab ${i === 0 ? 'active' : ''}" data-skill="${esc(s.id)}">
        ${s.emoji ? s.emoji + ' ' : ''}${esc(s.skill)}
      </button>`).join('');
  }

  /* ─── Interactions ────────────────────────────────────── */

  function animateProgress(root) {
    root.querySelectorAll('.st-progress-fill').forEach(fill => {
      const target = fill.dataset.progress;
      // Small delay so transition is visible on load
      requestAnimationFrame(() => {
        setTimeout(() => { fill.style.width = target + '%'; }, 80);
      });
    });
  }

  function bindTabs(root) {
    const tabs = root.querySelectorAll('.st-tab');
    const panels = root.querySelectorAll('.st-panel');

    tabs.forEach(tab => {
      tab.addEventListener('click', () => {
        const id = tab.dataset.skill;
        tabs.forEach(t => t.classList.toggle('active', t.dataset.skill === id));
        panels.forEach(p => p.classList.toggle('active', p.dataset.skill === id));
        // Re-animate progress bar for newly shown panel
        const panel = root.querySelector(`.st-panel[data-skill="${id}"]`);
        if (panel) animateProgress(panel);
      });
    });
  }

  function bindCards(root) {
    root.addEventListener('click', e => {
      const card = e.target.closest('.st-card');
      if (!card) return;
      const detail = card.querySelector('.st-detail');
      const isOpen = card.classList.contains('open');
      card.classList.toggle('open', !isOpen);
      card.setAttribute('aria-expanded', String(!isOpen));
      if (detail) {
        detail.classList.toggle('open', !isOpen);
        detail.setAttribute('aria-hidden', String(isOpen));
      }
    });

    // Keyboard support
    root.addEventListener('keydown', e => {
      if ((e.key === 'Enter' || e.key === ' ') && e.target.classList.contains('st-card')) {
        e.preventDefault();
        e.target.click();
      }
    });
  }

  /* ─── Bootstrap ───────────────────────────────────────── */

  function init(skillsData) {
    const mount = document.getElementById('skills-timeline');
    if (!mount) { console.warn('[SkillsTimeline] No #skills-timeline element found.'); return; }

    mount.classList.add('st-root');
    mount.innerHTML = `
      <header class="st-page-header">
        <h1 class="st-page-title">Learning log</h1>
        <p class="st-page-subtitle">Documenting the journey, not just the destination.</p>
      </header>
      <nav class="st-tabs" role="tablist">${renderTabs(skillsData)}</nav>
      ${skillsData.map(renderPanel).join('')}
      <p class="st-footer">Click any milestone to expand</p>
    `;

    bindTabs(mount);
    bindCards(mount);
    animateProgress(mount.querySelector('.st-panel.active'));
  }

  /* ─── Entry point ─────────────────────────────────────── */

  function boot() {
    const mount = document.getElementById('skills-timeline');
    const src = (mount && mount.dataset.src) || 'data/skills.json';

    fetch(src)
      .then(r => {
        if (!r.ok) throw new Error(`Failed to load ${src}: ${r.status}`);
        return r.json();
      })
      .then(data => init(data))
      .catch(err => {
        console.error('[SkillsTimeline]', err);
        const el = document.getElementById('skills-timeline');
        if (el) {
          el.innerHTML = `<p style="color:#c04828;font-size:.85rem;">Could not load skills data. Check the console for details.</p>`;
        }
      });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }

})();
