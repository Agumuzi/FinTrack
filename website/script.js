(() => {
  'use strict';
  const root = document.documentElement;
  const media = window.matchMedia('(prefers-color-scheme: dark)');
  const toggle = document.querySelector('.theme-toggle');
  function dark() { return root.dataset.theme ? root.dataset.theme === 'dark' : media.matches; }
  function updateThemeButton() {
    const isDark = dark();
    toggle.setAttribute('aria-label', isDark ? '切换浅色模式' : '切换深色模式');
    document.querySelector('meta[name="theme-color"]').content = isDark ? '#171c19' : '#f6f5f1';
  }
  toggle.addEventListener('click', () => {
    root.dataset.theme = dark() ? 'light' : 'dark';
    try { localStorage.setItem('fintrack-site-theme', root.dataset.theme); } catch (_) {}
    updateThemeButton();
  });
  media.addEventListener('change', updateThemeButton);
  updateThemeButton();

  const menuButton = document.querySelector('.menu-toggle');
  const nav = document.querySelector('#primary-nav');
  function closeMenu() {
    nav.classList.remove('is-open');
    menuButton.setAttribute('aria-expanded', 'false');
    menuButton.setAttribute('aria-label', '展开导航');
  }
  menuButton.addEventListener('click', () => {
    const open = nav.classList.toggle('is-open');
    menuButton.setAttribute('aria-expanded', String(open));
    menuButton.setAttribute('aria-label', open ? '收起导航' : '展开导航');
  });
  nav.addEventListener('click', event => { if (event.target.closest('a')) closeMenu(); });
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && nav.classList.contains('is-open')) { closeMenu(); menuButton.focus(); }
  });
  document.addEventListener('click', event => { if (!event.target.closest('.nav-wrap')) closeMenu(); });

  const screens = {
    records: {alt: 'FinTrack v1.0 收支账目界面', description: '按日期、类别与币种整理账目，原币和本位币金额都有迹可循。'},
    finance: {alt: 'FinTrack v1.0 财务计划界面', description: '在存款、贷款和周期记录间，管理与核对财务计划。示例“Logo”代表用户自定义图片：与银行名称关联保存，下次自动匹配。'},
    exchange: {alt: 'FinTrack v1.0 汇率工作区', description: '查询、换算并回看汇率，记账与菜单栏的数据来源可以分别选择。'},
    settings: {alt: 'FinTrack v1.0 原生备份与导出界面', description: '保存原生完整备份，或用四类 CSV 模板交换数据；恢复前先保留安全副本。'}
  };
  const tabs = [...document.querySelectorAll('[data-screen]')];
  const image = document.querySelector('#gallery-image');
  const panel = document.querySelector('#screen-panel');
  const description = document.querySelector('#gallery-description');
  let imageRequest = 0;
  function selectScreen(tab, focus = false) {
    const key = tab.dataset.screen;
    const screen = screens[key];
    tabs.forEach(item => {
      const selected = item === tab;
      item.setAttribute('aria-selected', String(selected));
      item.tabIndex = selected ? 0 : -1;
    });
    panel.setAttribute('aria-labelledby', tab.id);
    description.textContent = screen.description;
    image.alt = screen.alt;
    const request = ++imageRequest;
    image.classList.add('is-changing');
    const next = new Image();
    next.onload = () => {
      if (request !== imageRequest) return;
      image.src = next.src;
      image.classList.remove('is-changing');
    };
    next.onerror = () => {
      if (request !== imageRequest) return;
      image.src = next.src;
      image.classList.remove('is-changing');
    };
    next.src = `./assets/screenshots/${key}.png`;
    if (focus) tab.focus();
  }
  tabs.forEach((tab, index) => {
    tab.addEventListener('click', () => selectScreen(tab));
    tab.addEventListener('keydown', event => {
      let next;
      if (event.key === 'ArrowRight') next = tabs[(index + 1) % tabs.length];
      if (event.key === 'ArrowLeft') next = tabs[(index + tabs.length - 1) % tabs.length];
      if (event.key === 'Home') next = tabs[0];
      if (event.key === 'End') next = tabs[tabs.length - 1];
      if (next) { event.preventDefault(); selectScreen(next, true); }
    });
  });

  document.querySelector('#copy-checksum').addEventListener('click', async () => {
    const value = document.querySelector('#checksum-value').textContent.trim();
    const status = document.querySelector('#copy-status');
    try {
      await navigator.clipboard.writeText(value);
      status.textContent = '已复制';
    } catch (_) {
      const range = document.createRange();
      range.selectNodeContents(document.querySelector('#checksum-value'));
      const selection = window.getSelection();
      selection.removeAllRanges(); selection.addRange(range);
      status.textContent = '请复制已选中的校验值';
    }
  });

  if ('IntersectionObserver' in window && !window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    root.classList.add('js-motion');
    const observer = new IntersectionObserver(entries => entries.forEach(entry => {
      if (entry.isIntersecting) { entry.target.classList.add('is-visible'); observer.unobserve(entry.target); }
    }), {threshold: 0.08});
    document.querySelectorAll('.reveal').forEach(element => observer.observe(element));
  }
})();
