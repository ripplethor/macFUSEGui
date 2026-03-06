import { mkdir, readdir, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  localeDefinitions,
  pageDefinitions,
  siteConfig,
  siteContent,
} from "./docs_content.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..");
const docsDir = path.join(repoRoot, "docs");
const posix = path.posix;
const pageById = new Map(pageDefinitions.map((page) => [page.id, page]));
const localeBySlug = new Map(localeDefinitions.map((locale) => [locale.slug, locale]));
const buildDate = new Date().toISOString().slice(0, 10);

const spaceCanvasMarkup = `
<div class="space-canvas fixed inset-0 z-0 pointer-events-none" aria-hidden="true">
  <div class="space-gradient space-gradient-light"></div>
  <div class="space-gradient space-gradient-dark"></div>
  <div class="nebula-cloud nebula-cloud-a"></div>
  <div class="nebula-cloud nebula-cloud-b"></div>
  <div class="nebula-cloud nebula-cloud-c"></div>
  <div class="nebula-cloud nebula-cloud-d"></div>
  <div class="space-dust"></div>
  <div class="starfield starfield-far"></div>
  <div class="starfield starfield-mid"></div>
  <div class="starfield starfield-near"></div>
  <div class="starfield star-glints"></div>
  <div class="shooting-stars">
    <div class="shooting-star"></div>
    <div class="shooting-star"></div>
    <div class="shooting-star"></div>
  </div>
  <div class="shooting-stars-reverse">
    <div class="shooting-star reverse"></div>
    <div class="shooting-star reverse"></div>
  </div>
  <div class="space-vignette"></div>
</div>
<div aria-hidden="true" id="theme-fade-layer"></div>`;

const themeInitScript = `
(function () {
  try {
    const storedTheme = localStorage.getItem("theme");
    const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches;

    if (storedTheme === "dark") {
      document.documentElement.classList.add("dark");
    } else if (storedTheme === "light") {
      document.documentElement.classList.remove("dark");
    } else if (prefersDark) {
      document.documentElement.classList.add("dark");
    }
  } catch (error) {
  }
})();
`.trim();

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function getOutputRelativePath(locale, page) {
  if (locale.slug === "en") {
    return page.fileName;
  }
  if (page.id === "home") {
    return posix.join(locale.slug, "index.html");
  }
  return posix.join(locale.slug, page.fileName);
}

function getPublicUrl(locale, page) {
  if (locale.slug === "en") {
    return page.id === "home"
      ? `${siteConfig.siteUrl}/`
      : `${siteConfig.siteUrl}/${page.fileName}`;
  }
  return page.id === "home"
    ? `${siteConfig.siteUrl}/${locale.slug}/`
    : `${siteConfig.siteUrl}/${locale.slug}/${page.fileName}`;
}

function relativeHref(currentLocale, currentPage, targetRelativePath) {
  const fromDir = posix.dirname(getOutputRelativePath(currentLocale, currentPage));
  const rel = posix.relative(fromDir === "." ? "" : fromDir, targetRelativePath);
  return rel || ".";
}

function pageHref(currentLocale, currentPage, targetLocale, targetPage) {
  const rawTarget = getOutputRelativePath(targetLocale, targetPage);
  let rel = relativeHref(currentLocale, currentPage, rawTarget);
  if (targetPage.id === "home") {
    if (rel === "index.html") {
      return "./";
    }
    if (rel.endsWith("/index.html")) {
      return rel.slice(0, -("index.html".length));
    }
  }
  return rel;
}

function assetHref(currentLocale, currentPage, assetPath) {
  return relativeHref(currentLocale, currentPage, assetPath);
}

function renderAction(action, currentLocale, currentPage, localeContent) {
  const baseClasses =
    action.style === "primary"
      ? "inline-flex items-center justify-center rounded-full bg-blue-600 px-5 py-3 font-semibold text-white shadow-[0_0_18px_rgba(37,99,235,0.35)] hover:bg-blue-700"
      : "inline-flex items-center justify-center rounded-full border border-gray-200 px-5 py-3 font-semibold text-gray-900 hover:bg-white/40 dark:border-white/10 dark:text-white dark:hover:bg-gray-800/60";

  let href = "#";
  let label = action.labelKey ? localeContent.ui.actions[action.labelKey] : "";
  let id = action.id ? ` id="${escapeHtml(action.id)}"` : "";

  if (action.kind === "download") {
    href = siteConfig.releasesUrl;
    label = label || localeContent.ui.actions.downloadLatest;
  } else if (action.kind === "repo") {
    href = siteConfig.repoUrl;
    label = label || localeContent.ui.actions.viewSource;
  } else if (action.kind === "page") {
    const targetPage = pageById.get(action.pageId);
    href = pageHref(currentLocale, currentPage, currentLocale, targetPage);
    label = label || siteContent[currentLocale.slug].pages[action.pageId].cardTitle;
  }

  return `<a class="${baseClasses}" href="${escapeHtml(href)}"${id}>${escapeHtml(label)}</a>`;
}

function renderLocaleSwitcher(currentLocale, currentPage, localeContent, compact = false) {
  const wrapperClasses = compact
    ? "min-w-[9rem]"
    : "w-full sm:w-auto sm:min-w-[11rem]";
  return `
    <div class="${wrapperClasses}">
      <label class="sr-only" for="locale-switcher-${escapeHtml(currentPage.id)}-${compact ? "compact" : "footer"}">${escapeHtml(localeContent.ui.labels.localeSwitcher)}</label>
      <select
        id="locale-switcher-${escapeHtml(currentPage.id)}-${compact ? "compact" : "footer"}"
        class="glass-panel w-full rounded-full border border-white/20 bg-white/70 px-3 py-2 text-sm font-medium text-gray-700 focus:outline-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-900/70 dark:text-gray-200"
        aria-label="${escapeHtml(localeContent.ui.languageLabel)}"
        onchange="if(this.value){window.location.href=this.value;}"
      >
        ${localeDefinitions
          .map((locale) => {
            const targetPage = pageById.get(currentPage.id);
            const selected = locale.slug === currentLocale.slug ? " selected" : "";
            const href = pageHref(currentLocale, currentPage, locale, targetPage);
            return `<option value="${escapeHtml(href)}"${selected}>${escapeHtml(locale.nativeLabel)}</option>`;
          })
          .join("")}
      </select>
    </div>`;
}

function renderHeader(currentLocale, currentPage, localeContent) {
  const navItems = ["home", "product", "sshfs", "install", "troubleshooting"];
  return `
    <header class="sticky top-0 z-50 border-b border-white/10 glass-panel">
      <div class="mx-auto flex h-20 max-w-7xl items-center justify-between gap-4 px-4 sm:px-6 lg:px-8">
        <a class="group flex items-center space-x-3" href="${escapeHtml(pageHref(currentLocale, currentPage, currentLocale, pageById.get("home")))}">
          <div class="relative h-9 w-9 overflow-hidden rounded-xl ring-1 ring-white/25 shadow-[0_8px_20px_rgba(8,25,66,0.35)]">
            <img
              alt="${escapeHtml(localeContent.brandAlt)}"
              class="h-full w-full object-cover"
              decoding="async"
              height="36"
              src="${escapeHtml(assetHref(currentLocale, currentPage, "assets/brand-icon.webp"))}"
              title="${escapeHtml(localeContent.brandAlt)}"
              width="36"
            />
          </div>
          <span class="text-xl font-bold tracking-tight text-gray-900 dark:text-white">macFUSE<span class="text-blue-600 dark:text-blue-400">Gui</span></span>
        </a>
        <nav class="hidden items-center gap-5 text-sm font-medium text-gray-600 dark:text-gray-300 md:flex">
          ${navItems
            .map((pageId) => {
              const targetPage = pageById.get(pageId);
              const isActive = currentPage.id === pageId;
              const classes = isActive
                ? "text-blue-600 dark:text-blue-400"
                : "hover:text-blue-600 dark:hover:text-blue-400";
              return `<a class="${classes}" href="${escapeHtml(pageHref(currentLocale, currentPage, currentLocale, targetPage))}">${escapeHtml(localeContent.ui.nav[pageId])}</a>`;
            })
            .join("")}
        </nav>
        <div class="flex items-center gap-3">
          ${renderLocaleSwitcher(currentLocale, currentPage, localeContent, true)}
          <button
            aria-label="${escapeHtml(localeContent.ui.labels.themeToggle)}"
            class="rounded-full p-2 text-gray-600 backdrop-blur-sm hover:bg-gray-200/50 focus:outline-none focus:ring-2 focus:ring-blue-500 dark:text-gray-300 dark:hover:bg-gray-800/50"
            id="theme-toggle"
          >
            <span
              class="sr-only"
              data-dark-label="${escapeHtml(localeContent.ui.labels.switchToDarkMode)}"
              data-light-label="${escapeHtml(localeContent.ui.labels.switchToLightMode)}"
              id="theme-toggle-label"
            >${escapeHtml(localeContent.ui.labels.switchToDarkMode)}</span>
            <svg aria-hidden="true" class="hidden h-5 w-5 text-yellow-400 dark:block" fill="none" focusable="false" viewBox="0 0 24 24" stroke="currentColor">
              <path d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"></path>
            </svg>
            <svg aria-hidden="true" class="block h-5 w-5 text-gray-600 dark:hidden" fill="none" focusable="false" viewBox="0 0 24 24" stroke="currentColor">
              <path d="M20.354 15.354A9 9 0 018.646 3.646 9.003 9.003 0 0012 21a9.003 9.003 0 008.354-5.646z" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"></path>
            </svg>
          </button>
        </div>
      </div>
    </header>`;
}

function renderFooter(currentLocale, currentPage, localeContent) {
  return `
    <footer class="relative z-10 mt-16 border-t border-gray-200 bg-white py-16 dark:border-white/5 dark:bg-gray-950">
      <div class="mx-auto flex max-w-7xl flex-col gap-6 px-4 sm:px-6 lg:px-8 md:flex-row md:items-center md:justify-between">
        <div class="text-center md:text-left">
          <span class="text-xl font-bold tracking-tight text-gray-900 dark:text-white">macFUSEGui</span>
          <p class="mt-2 text-sm text-gray-600 dark:text-white/50">© <span id="current-year">2026</span> ${escapeHtml(localeContent.ui.copyright)}</p>
          <p class="mt-2 text-sm font-medium text-gray-700 dark:text-white/50">
            ${escapeHtml(localeContent.ui.footer.license).replace("LICENSE", `<a class="underline underline-offset-4 decoration-blue-500/50 hover:decoration-blue-500" href="${siteConfig.licenseUrl}">LICENSE</a>`)}
          </p>
        </div>
        <div class="flex flex-col items-center gap-4 md:items-end">
          <div class="flex flex-wrap items-center justify-center gap-5 text-sm text-gray-600 dark:text-white/50">
            <a class="hover:text-blue-600 dark:hover:text-blue-400" href="${escapeHtml(pageHref(currentLocale, currentPage, currentLocale, pageById.get("home")))}">${escapeHtml(localeContent.ui.footer.home)}</a>
            <a class="hover:text-blue-600 dark:hover:text-blue-400" href="${escapeHtml(pageHref(currentLocale, currentPage, currentLocale, pageById.get("install")))}">${escapeHtml(localeContent.ui.footer.install)}</a>
            <a class="hover:text-blue-600 dark:hover:text-blue-400" href="${escapeHtml(pageHref(currentLocale, currentPage, currentLocale, pageById.get("troubleshooting")))}">${escapeHtml(localeContent.ui.footer.troubleshooting)}</a>
            <a class="hover:text-blue-600 dark:hover:text-blue-400" href="${siteConfig.repoUrl}" id="footer-github-btn">${escapeHtml(localeContent.ui.footer.github)}</a>
          </div>
          ${renderLocaleSwitcher(currentLocale, currentPage, localeContent, false)}
        </div>
      </div>
    </footer>`;
}

function renderCodeBlock(code) {
  return `
    <div class="overflow-hidden rounded-2xl border border-white/10 bg-gray-950/90 text-gray-100">
      <pre class="overflow-x-auto p-5 text-sm leading-relaxed"><code class="font-mono">${escapeHtml(code)}</code></pre>
    </div>`;
}

function renderCopySection(section, hasCompactTop = false) {
  return `
    <section class="glass-panel rounded-3xl p-8 sm:p-10 ${hasCompactTop ? "" : "space-y-5"}">
      <h2 class="text-3xl font-bold tracking-tight text-gray-900 dark:text-white">${section.title}</h2>
      ${(section.paragraphs ?? [])
        .map(
          (paragraph) =>
            `<p class="mt-5 leading-relaxed text-gray-700 dark:text-gray-300">${paragraph}</p>`,
        )
        .join("")}
      ${section.code ? `<div class="mt-5">${renderCodeBlock(section.code)}</div>` : ""}
      ${section.bullets?.length
        ? `<ul class="mt-5 list-disc space-y-3 pl-6 leading-relaxed text-gray-700 dark:text-gray-300">${section.bullets.map((item) => `<li>${item}</li>`).join("")}</ul>`
        : ""}
      ${section.ordered?.length
        ? `<ol class="mt-5 list-decimal space-y-3 pl-6 leading-relaxed text-gray-700 dark:text-gray-300">${section.ordered.map((item) => `<li>${item}</li>`).join("")}</ol>`
        : ""}
      ${section.actions?.length
        ? `<div class="mt-6 flex flex-wrap gap-3">${section.actions
            .map((action) => renderAction(action, arguments[1], arguments[2], arguments[3]))
            .join("")}</div>`
        : ""}`;
}

function renderGuideCopySection(section, currentLocale, currentPage, localeContent) {
  return `
    <section class="glass-panel rounded-3xl p-8 sm:p-10">
      <h2 class="text-3xl font-bold tracking-tight text-gray-900 dark:text-white">${section.title}</h2>
      ${(section.paragraphs ?? [])
        .map(
          (paragraph) =>
            `<p class="mt-5 leading-relaxed text-gray-700 dark:text-gray-300">${paragraph}</p>`,
        )
        .join("")}
      ${section.code ? `<div class="mt-5">${renderCodeBlock(section.code)}</div>` : ""}
      ${section.bullets?.length
        ? `<ul class="mt-5 list-disc space-y-3 pl-6 leading-relaxed text-gray-700 dark:text-gray-300">${section.bullets.map((item) => `<li>${item}</li>`).join("")}</ul>`
        : ""}
      ${section.ordered?.length
        ? `<ol class="mt-5 list-decimal space-y-3 pl-6 leading-relaxed text-gray-700 dark:text-gray-300">${section.ordered.map((item) => `<li>${item}</li>`).join("")}</ol>`
        : ""}
      ${section.actions?.length
        ? `<div class="mt-6 flex flex-wrap gap-3">${section.actions
            .map((action) => renderAction(action, currentLocale, currentPage, localeContent))
            .join("")}</div>`
        : ""}
    </section>`;
}

function renderCardsSection(section) {
  const columnsClass =
    section.columns === 2
      ? "md:grid-cols-2"
      : section.columns === 3
        ? "lg:grid-cols-3"
        : "md:grid-cols-2";
  return `
    <section class="glass-panel rounded-3xl p-8 sm:p-10">
      <h2 class="text-3xl font-bold tracking-tight text-gray-900 dark:text-white">${section.title}</h2>
      ${section.intro ? `<p class="mt-5 leading-relaxed text-gray-700 dark:text-gray-300">${section.intro}</p>` : ""}
      <div class="mt-6 grid gap-6 ${columnsClass}">
        ${section.cards
          .map(
            (card) => `
              <article class="rounded-3xl border border-white/15 bg-white/45 p-6 shadow-sm dark:border-white/10 dark:bg-black/20">
                <h3 class="text-xl font-bold text-gray-900 dark:text-white">${card.title}</h3>
                <p class="mt-3 leading-relaxed text-gray-700 dark:text-gray-300">${card.body}</p>
              </article>`,
          )
          .join("")}
      </div>
    </section>`;
}

function renderGuideCards(localeContent, currentLocale, currentPage) {
  const guidePages = pageDefinitions.filter((page) => page.id !== "home");
  return `
    <section class="glass-panel rounded-3xl p-8 sm:p-10" data-related-guides="true">
      <h2 class="text-2xl font-bold tracking-tight text-gray-900 dark:text-white">${escapeHtml(localeContent.ui.labels.relatedGuides)}</h2>
      <div class="mt-6 grid gap-4 md:grid-cols-3">
        ${guidePages
          .filter((page) => page.id !== currentPage.id)
          .map((page) => {
            const targetContent = localeContent.pages[page.id];
            return `
              <a class="rounded-2xl border border-white/15 p-5 transition-colors hover:border-blue-400/40 glass-panel" href="${escapeHtml(pageHref(currentLocale, currentPage, currentLocale, page))}">
                <h3 class="text-xl font-bold text-gray-900 dark:text-white">${escapeHtml(targetContent.cardTitle)}</h3>
                <p class="mt-2 leading-relaxed text-gray-700 dark:text-gray-300">${targetContent.cardDescription}</p>
              </a>`;
          })
          .join("")}
      </div>
    </section>`;
}

function renderFaq(homeContent) {
  return `
    <section class="py-24" id="faq">
      <div class="mx-auto max-w-4xl px-4 sm:px-6 lg:px-8">
        <h2 class="text-center text-4xl font-bold tracking-tight text-gray-900 dark:text-white">${homeContent.faq.title}</h2>
        <p class="mx-auto mt-4 max-w-2xl text-center text-lg text-gray-600 dark:text-gray-400">${homeContent.faq.intro}</p>
        <div class="mt-12 space-y-4">
          ${homeContent.faq.items
            .map(
              (item, index) => `
                <section class="overflow-hidden rounded-2xl glass-panel hover:shadow-lg">
                  <h3>
                    <button
                      class="flex w-full items-center justify-between px-8 py-6 text-left focus:outline-none focus-visible:ring-2 focus-visible:ring-blue-500"
                      id="faq-trigger-${index + 1}"
                      aria-controls="faq-${index + 1}"
                      aria-expanded="false"
                      data-accordion-trigger
                    >
                      <span class="text-lg font-bold text-gray-900 dark:text-gray-100">${item.question}</span>
                      <svg aria-hidden="true" class="h-5 w-5 text-gray-500 transform" fill="none" focusable="false" viewBox="0 0 24 24" stroke="currentColor">
                        <path d="M19 9l-7 7-7-7" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"></path>
                      </svg>
                    </button>
                  </h3>
                  <div
                    class="faq-panel px-8 leading-relaxed text-gray-600 dark:text-gray-400"
                    aria-hidden="true"
                    aria-labelledby="faq-trigger-${index + 1}"
                    data-accordion-panel
                    id="faq-${index + 1}"
                    role="region"
                  >
                    <div class="faq-inner pb-6">${item.answer}</div>
                  </div>
                </section>`,
            )
            .join("")}
        </div>
      </div>
    </section>`;
}

function renderHomePage(currentLocale, currentPage, localeContent) {
  const homeContent = localeContent.pages.home;
  const guidePages = pageDefinitions.filter((page) => page.id !== "home");
  const stepLabel = localeContent.ui.labels.stepLabel;
  const spotlight = homeContent.heroSpotlight;

  return `
    <main class="relative z-10">
      <section class="overflow-hidden pt-24 pb-24 sm:pt-32 sm:pb-32">
        <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
          <div class="mx-auto max-w-4xl text-center">
            <p class="text-sm font-semibold uppercase tracking-[0.24em] text-blue-600 dark:text-blue-400">${homeContent.hero.eyebrow}</p>
            <h1 class="mt-6 text-6xl font-black leading-none tracking-tight text-gray-900 dark:text-white sm:text-8xl">
              <span class="inline-block [word-spacing:0.10em]">${homeContent.hero.titleTop}</span><br />
              <span class="inline-block bg-gradient-to-r from-blue-600 via-indigo-500 to-purple-600 bg-clip-text text-transparent [word-spacing:0.10em]">${homeContent.hero.titleBottom}</span>
            </h1>
            <p class="mx-auto mt-6 max-w-3xl text-xl font-medium leading-relaxed text-gray-700 dark:text-gray-300">${homeContent.hero.lead}</p>
            <p class="mx-auto mt-4 max-w-3xl text-base leading-relaxed text-gray-600 dark:text-gray-300 sm:text-lg">${homeContent.hero.supporting}</p>
            <div class="mt-10 flex flex-wrap justify-center gap-4">
              ${homeContent.hero.actions.map((action) => renderAction(action, currentLocale, currentPage, localeContent)).join("")}
            </div>
          </div>
          <div class="hero-stage relative mx-auto mt-16 max-w-6xl overflow-hidden rounded-[2rem] border border-white/15 bg-[url('${assetHref(currentLocale, currentPage, "assets/hero-bg.webp")}')] bg-cover bg-center shadow-2xl">
            <div class="absolute inset-0 bg-black/45 backdrop-blur-sm"></div>
            <div class="relative grid gap-8 px-6 py-8 md:grid-cols-[1.1fr_0.9fr] md:px-10 md:py-10">
              <div class="glass-panel rounded-3xl border border-white/10 p-6 text-left md:p-8">
                <div class="flex items-center justify-between">
                  <div class="text-sm font-bold uppercase tracking-[0.18em] text-blue-600 dark:text-blue-400">macFUSEGui</div>
                  <div class="font-mono text-xs text-gray-500" id="hero-version">${escapeHtml(spotlight.versionFallback)}</div>
                </div>
                <p class="mt-4 text-lg font-semibold text-gray-900 dark:text-white">${escapeHtml(spotlight.title)}</p>
                <ul class="mt-5 space-y-3 leading-relaxed text-gray-700 dark:text-gray-300">
                  ${spotlight.bullets.map((bullet) => `<li>${escapeHtml(bullet)}</li>`).join("")}
                </ul>
              </div>
              <div class="glass-panel rounded-3xl border border-white/10 p-6 text-left md:p-8">
                <div class="text-sm font-semibold uppercase tracking-[0.18em] text-blue-600 dark:text-blue-400">${homeContent.installSection.title}</div>
                <div class="mt-5 space-y-4">
                  ${homeContent.installSection.checklist
                    .map(
                      (step, index) => `
                        <div class="rounded-2xl border border-white/10 bg-white/35 p-4 dark:bg-black/20">
                          <div class="text-sm font-bold uppercase tracking-[0.16em] text-blue-600 dark:text-blue-400">${escapeHtml(stepLabel)} ${index + 1}</div>
                          <p class="mt-2 text-base font-semibold text-gray-900 dark:text-white">${step.title}</p>
                          <p class="mt-2 leading-relaxed text-gray-700 dark:text-gray-300">${step.body}</p>
                        </div>`,
                    )
                    .join("")}
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      <section class="py-24" id="guides">
        <div class="mx-auto max-w-6xl px-4 sm:px-6 lg:px-8">
          <div class="mx-auto max-w-3xl text-center">
            <h2 class="text-4xl font-bold tracking-tight text-gray-900 dark:text-white">${homeContent.guideSection.title}</h2>
            <p class="mt-4 text-lg text-gray-600 dark:text-gray-400">${homeContent.guideSection.intro}</p>
          </div>
          <div class="mt-12 grid gap-6 md:grid-cols-2 xl:grid-cols-4">
            ${guidePages
              .map((page) => {
                const pageContent = localeContent.pages[page.id];
                return `
                  <a class="glass-panel rounded-3xl border border-white/15 p-6 transition-transform hover:-translate-y-1 hover:border-blue-400/40" href="${escapeHtml(pageHref(currentLocale, currentPage, currentLocale, page))}">
                    <div class="text-sm font-semibold uppercase tracking-[0.18em] text-blue-600 dark:text-blue-400">${localeContent.ui.labels.guideSection}</div>
                    <h3 class="mt-3 text-2xl font-bold text-gray-900 dark:text-white">${escapeHtml(pageContent.cardTitle)}</h3>
                    <p class="mt-3 leading-relaxed text-gray-700 dark:text-gray-300">${pageContent.cardDescription}</p>
                  </a>`;
              })
              .join("")}
          </div>
        </div>
      </section>

      <section class="py-24" id="features">
        <div class="mx-auto max-w-6xl px-4 sm:px-6 lg:px-8">
          <div class="mx-auto max-w-3xl text-center">
            <h2 class="text-4xl font-bold tracking-tight text-gray-900 dark:text-white">${homeContent.benefitsSection.title}</h2>
            <p class="mt-4 text-lg text-gray-600 dark:text-gray-400">${homeContent.benefitsSection.intro}</p>
          </div>
          <div class="mt-12 grid gap-6 md:grid-cols-2 xl:grid-cols-3">
            ${homeContent.benefitsSection.cards
              .map(
                (card) => `
                  <article class="glass-panel rounded-3xl p-8 shadow-sm">
                    <h3 class="text-xl font-bold text-gray-900 dark:text-white">${card.title}</h3>
                    <p class="mt-3 leading-relaxed text-gray-700 dark:text-gray-300">${card.body}</p>
                  </article>`,
              )
              .join("")}
          </div>
        </div>
      </section>

      <section class="py-24" id="install">
        <div class="mx-auto max-w-6xl px-4 sm:px-6 lg:px-8">
          <div class="mx-auto max-w-3xl text-center">
            <h2 class="text-4xl font-bold tracking-tight text-gray-900 dark:text-white">${homeContent.installSection.title}</h2>
            <p class="mt-4 text-lg text-gray-600 dark:text-gray-400">${homeContent.installSection.intro}</p>
          </div>
          <div class="mt-12 space-y-8">
            <section class="glass-panel rounded-3xl p-8 sm:p-10">
              <h3 class="text-2xl font-bold tracking-tight text-gray-900 dark:text-white">${homeContent.installSection.methodsTitle}</h3>
              <div class="mt-6 grid gap-6 md:grid-cols-3">
                ${homeContent.installSection.methods
                  .map(
                    (method) => `
                      <article class="rounded-2xl border border-white/10 bg-white/40 p-5 dark:bg-black/20">
                        <p class="text-lg font-bold text-gray-900 dark:text-white">${method.title}</p>
                        <p class="mt-3 leading-relaxed text-gray-700 dark:text-gray-300">${method.body}</p>
                        ${method.code ? `<div class="mt-4">${renderCodeBlock(method.code)}</div>` : `<div class="mt-4">${renderAction({ kind: "download", style: "primary", labelKey: "openReleasePage" }, currentLocale, currentPage, localeContent)}</div>`}
                      </article>`,
                  )
                  .join("")}
              </div>
            </section>
            <section class="grid gap-8 md:grid-cols-2">
              <div class="glass-panel rounded-3xl p-8">
                <h3 class="text-2xl font-bold tracking-tight text-gray-900 dark:text-white">${homeContent.installSection.prerequisitesTitle}</h3>
                ${homeContent.installSection.prerequisitesParagraphs
                  .map((paragraph) => `<p class="mt-4 leading-relaxed text-gray-700 dark:text-gray-300">${paragraph}</p>`)
                  .join("")}
                <div class="mt-5">${renderCodeBlock(homeContent.installSection.prerequisitesCode)}</div>
              </div>
              <div class="glass-panel rounded-3xl p-8">
                <h3 class="text-2xl font-bold tracking-tight text-gray-900 dark:text-white">${homeContent.installSection.downloadTitle}</h3>
                ${homeContent.installSection.downloadParagraphs
                  .map((paragraph) => `<p class="mt-4 leading-relaxed text-gray-700 dark:text-gray-300">${paragraph}</p>`)
                  .join("")}
                <div class="mt-5">${renderCodeBlock(homeContent.installSection.downloadCode)}</div>
              </div>
            </section>
            <section class="glass-panel rounded-3xl p-8 sm:p-10">
              <h3 class="text-2xl font-bold tracking-tight text-gray-900 dark:text-white">${homeContent.installSection.checklistTitle}</h3>
              <div class="mt-6 grid gap-6 md:grid-cols-3">
                ${homeContent.installSection.checklist
                  .map(
                    (step, index) => `
                      <article class="rounded-2xl border border-white/10 bg-white/40 p-5 dark:bg-black/20">
                        <div class="text-sm font-bold uppercase tracking-[0.18em] text-blue-600 dark:text-blue-400">${escapeHtml(stepLabel)} ${index + 1}</div>
                        <p class="mt-3 text-lg font-bold text-gray-900 dark:text-white">${step.title}</p>
                        <p class="mt-3 leading-relaxed text-gray-700 dark:text-gray-300">${step.body}</p>
                      </article>`,
                  )
                  .join("")}
              </div>
            </section>
          </div>
        </div>
      </section>

      <section class="py-24" id="how-it-works">
        <div class="mx-auto max-w-4xl px-4 sm:px-6 lg:px-8">
          <div class="glass-panel rounded-3xl p-8 sm:p-10">
            <h2 class="text-4xl font-bold tracking-tight text-gray-900 dark:text-white">${homeContent.howItWorks.title}</h2>
            <p class="mt-4 text-lg text-gray-700 dark:text-gray-300">${homeContent.howItWorks.intro}</p>
            <ul class="mt-6 space-y-4 leading-relaxed text-gray-700 dark:text-gray-300">
              ${homeContent.howItWorks.points.map((point) => `<li>${point}</li>`).join("")}
            </ul>
          </div>
        </div>
      </section>

      ${renderFaq(homeContent)}
    </main>`;
}

function renderGuidePage(currentLocale, currentPage, localeContent) {
  const pageContent = localeContent.pages[currentPage.id];

  return `
    <main class="relative z-10 py-20 sm:py-24">
      <div class="mx-auto max-w-5xl space-y-10 px-4 sm:px-6 lg:px-8">
        <nav class="text-sm text-gray-600 dark:text-gray-300" aria-label="${escapeHtml(localeContent.ui.labels.breadcrumb)}" data-breadcrumb="true">
          <ol class="flex flex-wrap items-center gap-2">
            <li><a class="hover:text-blue-600 dark:hover:text-blue-400" href="${escapeHtml(pageHref(currentLocale, currentPage, currentLocale, pageById.get("home")))}">${escapeHtml(localeContent.ui.labels.breadcrumbHome)}</a></li>
            <li aria-hidden="true">/</li>
            <li class="font-semibold text-gray-900 dark:text-white">${escapeHtml(pageContent.cardTitle)}</li>
          </ol>
        </nav>
        <section class="glass-panel rounded-3xl p-8 sm:p-12">
          <p class="text-sm font-semibold uppercase tracking-[0.24em] text-blue-600 dark:text-blue-400">${pageContent.hero.eyebrow}</p>
          <h1 class="mt-4 text-4xl font-black tracking-tight text-gray-900 dark:text-white sm:text-6xl">${escapeHtml(pageContent.cardTitle)}</h1>
          <p class="mt-6 max-w-3xl text-lg leading-relaxed text-gray-700 dark:text-gray-300 sm:text-xl">${pageContent.hero.lead}</p>
          <div class="mt-8 flex flex-wrap gap-3">
            ${pageContent.hero.actions.map((action) => renderAction(action, currentLocale, currentPage, localeContent)).join("")}
          </div>
        </section>
        ${pageContent.sections
          .map((section) =>
            section.type === "cards"
              ? renderCardsSection(section)
              : renderGuideCopySection(section, currentLocale, currentPage, localeContent),
          )
          .join("")}
        ${renderGuideCards(localeContent, currentLocale, currentPage)}
      </div>
    </main>`;
}

function buildStructuredData(currentLocale, currentPage, localeContent) {
  const pageContent = localeContent.pages[currentPage.id];
  const currentUrl = getPublicUrl(currentLocale, currentPage);
  const data = [
    {
      "@context": "https://schema.org",
      "@type": currentPage.id === "home" ? "WebSite" : "WebPage",
      name: pageContent.cardTitle,
      url: currentUrl,
      inLanguage: currentLocale.htmlLang,
      description: pageContent.metaDescription,
    },
  ];

  if (currentPage.id === "home") {
    data.push({
      "@context": "https://schema.org",
      "@type": "SoftwareApplication",
      name: "macFUSEGui",
      alternateName: "macFUSE GUI",
      url: currentUrl,
      operatingSystem: "macOS 13 or later",
      applicationCategory: "UtilitiesApplication",
      keywords: "macFUSE GUI, SSHFS, macOS, macFUSEGui",
      softwareRequirements: "macFUSE and sshfs",
      isAccessibleForFree: true,
      sameAs: [siteConfig.repoUrl],
      downloadUrl: siteConfig.releasesUrl,
      screenshot: `${siteConfig.siteUrl}/assets/og-image.webp`,
      description: pageContent.structuredDescription,
      offers: {
        "@type": "Offer",
        price: "0",
        priceCurrency: "USD",
      },
    });
    data.push({
      "@context": "https://schema.org",
      "@type": "FAQPage",
      mainEntity: pageContent.faq.items.map((item) => ({
        "@type": "Question",
        name: item.question,
        acceptedAnswer: {
          "@type": "Answer",
          text: item.answer.replace(/<[^>]+>/g, ""),
        },
      })),
    });
  } else {
    data.push({
      "@context": "https://schema.org",
      "@type": "BreadcrumbList",
      itemListElement: [
        {
          "@type": "ListItem",
          position: 1,
          name: localeContent.ui.labels.breadcrumbHome,
          item: getPublicUrl(currentLocale, pageById.get("home")),
        },
        {
          "@type": "ListItem",
          position: 2,
          name: pageContent.cardTitle,
          item: currentUrl,
        },
      ],
    });
  }

  return JSON.stringify(data, null, 2);
}

function buildHead(currentLocale, currentPage, localeContent) {
  const pageContent = localeContent.pages[currentPage.id];
  const pageUrl = getPublicUrl(currentLocale, currentPage);
  const cssHref = assetHref(currentLocale, currentPage, "assets/tailwind.generated.css");
  const siteCssHref = assetHref(currentLocale, currentPage, "assets/site.css");
  const siteJsHref = assetHref(currentLocale, currentPage, "assets/site.js");
  const ogImage = `${siteConfig.siteUrl}/assets/og-image.webp`;
  const faviconBase = assetHref(currentLocale, currentPage, "assets/favicon");
  const alternates = localeDefinitions
    .map((locale) => {
      const targetPage = pageById.get(currentPage.id);
      return `<link rel="alternate" hreflang="${locale.hreflang}" href="${getPublicUrl(locale, targetPage)}">`;
    })
    .join("\n");
  const xDefault = `<link rel="alternate" hreflang="x-default" href="${getPublicUrl(localeBySlug.get("en"), pageById.get(currentPage.id))}">`;
  const ogLocaleAlternates = localeDefinitions
    .filter((locale) => locale.slug !== currentLocale.slug)
    .map((locale) => `<meta property="og:locale:alternate" content="${locale.ogLocale}">`)
    .join("\n");

  return `
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>${escapeHtml(pageContent.title)}</title>
    <meta name="description" content="${escapeHtml(pageContent.metaDescription)}">
    <meta name="robots" content="index,follow,max-snippet:-1,max-image-preview:large,max-video-preview:-1">
    <meta name="application-name" content="macFUSEGui">
    <link rel="canonical" href="${pageUrl}">
    ${alternates}
    ${xDefault}
    <meta name="theme-color" media="(prefers-color-scheme: light)" content="#123677">
    <meta name="theme-color" media="(prefers-color-scheme: dark)" content="#071330">
    ${currentPage.id === "home" ? `<link rel="preload" href="${assetHref(currentLocale, currentPage, "assets/hero-bg.webp")}" as="image">` : ""}
    <link rel="apple-touch-icon" sizes="180x180" href="${faviconBase}/apple-touch-icon.png">
    <link rel="icon" type="image/png" sizes="32x32" href="${faviconBase}/favicon-32x32.png">
    <link rel="icon" type="image/png" sizes="16x16" href="${faviconBase}/favicon-16x16.png">
    <link rel="shortcut icon" href="${faviconBase}/favicon.ico">
    <link rel="manifest" href="${faviconBase}/site.webmanifest">
    <meta property="og:type" content="${currentPage.id === "home" ? "website" : "article"}">
    <meta property="og:url" content="${pageUrl}">
    <meta property="og:site_name" content="macFUSEGui">
    <meta property="og:locale" content="${currentLocale.ogLocale}">
    ${ogLocaleAlternates}
    <meta property="og:title" content="${escapeHtml(pageContent.title)}">
    <meta property="og:description" content="${escapeHtml(pageContent.metaDescription)}">
    <meta property="og:image" content="${ogImage}">
    <meta property="og:image:width" content="1200">
    <meta property="og:image:height" content="630">
    <meta property="og:image:type" content="image/webp">
    <meta property="og:image:alt" content="${escapeHtml(localeContent.brandAlt)}">
    <meta property="twitter:card" content="summary_large_image">
    <meta property="twitter:url" content="${pageUrl}">
    <meta property="twitter:title" content="${escapeHtml(pageContent.title)}">
    <meta property="twitter:description" content="${escapeHtml(pageContent.metaDescription)}">
    <meta property="twitter:image" content="${ogImage}">
    <meta property="twitter:image:alt" content="${escapeHtml(localeContent.brandAlt)}">
    <script type="application/ld+json">${buildStructuredData(currentLocale, currentPage, localeContent)}</script>
    <script>${themeInitScript}</script>
    <link rel="stylesheet" href="${cssHref}?v=20260306-03">
    <link rel="stylesheet" href="${siteCssHref}?v=20260306-03">
    ${currentPage.id === "home" ? `<noscript><style>.faq-panel{grid-template-rows:1fr;opacity:1}</style></noscript>` : ""}
    <script defer src="${siteJsHref}?v=20260306-03"></script>`;
}

function buildPageHtml(currentLocale, currentPage) {
  const localeContent = siteContent[currentLocale.slug];
  const body =
    currentPage.layout === "home"
      ? renderHomePage(currentLocale, currentPage, localeContent)
      : renderGuidePage(currentLocale, currentPage, localeContent);

  return `<!doctype html>
<html class="antialiased" lang="${currentLocale.htmlLang}">
  <head>${buildHead(currentLocale, currentPage, localeContent)}
  </head>
  <body class="bg-gray-50 text-gray-900 dark:bg-gray-950 dark:text-gray-100">
    ${spaceCanvasMarkup}
    ${renderHeader(currentLocale, currentPage, localeContent)}
    ${body}
    ${renderFooter(currentLocale, currentPage, localeContent)}
  </body>
</html>
`;
}

function buildSitemap() {
  const xhtmlNamespace = 'xmlns:xhtml="http://www.w3.org/1999/xhtml"';
  const entries = pageDefinitions
    .flatMap((page) =>
      localeDefinitions.map((locale) => {
        const url = getPublicUrl(locale, page);
        const alternates = localeDefinitions
          .map(
            (targetLocale) =>
              `    <xhtml:link rel="alternate" hreflang="${targetLocale.hreflang}" href="${getPublicUrl(targetLocale, page)}" />`,
          )
          .concat(
            `    <xhtml:link rel="alternate" hreflang="x-default" href="${getPublicUrl(localeBySlug.get("en"), page)}" />`,
          )
          .join("\n");
        return `  <url>
    <loc>${url}</loc>
    <lastmod>${buildDate}</lastmod>
    <changefreq>weekly</changefreq>
    <priority>${page.id === "home" ? "1.0" : "0.8"}</priority>
${alternates}
  </url>`;
      }),
    )
    .join("\n");

  return `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" ${xhtmlNamespace}>
${entries}
</urlset>
`;
}

async function ensureLocaleDirectories() {
  const localeDirs = localeDefinitions.filter((locale) => locale.slug !== "en");
  for (const locale of localeDirs) {
    await rm(path.join(docsDir, locale.slug), { force: true, recursive: true });
    await mkdir(path.join(docsDir, locale.slug), { recursive: true });
  }
}

async function preserveDocsRootFiles() {
  const entries = await readdir(docsDir, { withFileTypes: true });
  for (const entry of entries) {
    if (!entry.isDirectory()) {
      continue;
    }
    if (!localeBySlug.has(entry.name) || entry.name === "en") {
      continue;
    }
    await rm(path.join(docsDir, entry.name), { recursive: true, force: true });
  }
}

async function writePages() {
  for (const locale of localeDefinitions) {
    for (const page of pageDefinitions) {
      const outputPath =
        locale.slug === "en"
          ? path.join(docsDir, page.fileName)
          : path.join(docsDir, locale.slug, page.fileName);
      await mkdir(path.dirname(outputPath), { recursive: true });
      await writeFile(outputPath, buildPageHtml(locale, page), "utf8");
      console.log(`Generated ${path.relative(repoRoot, outputPath)}`);
    }
  }
}

async function writeSitemap() {
  const sitemapPath = path.join(docsDir, "sitemap.xml");
  await writeFile(sitemapPath, buildSitemap(), "utf8");
  console.log(`Generated ${path.relative(repoRoot, sitemapPath)}`);
}

async function main() {
  await preserveDocsRootFiles();
  await ensureLocaleDirectories();
  await writePages();
  await writeSitemap();
}

await main();
