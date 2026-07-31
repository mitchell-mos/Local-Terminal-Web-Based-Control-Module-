"use client";

import type { FormEvent, KeyboardEvent as ReactKeyboardEvent } from "react";
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";

type Host = "localhost" | "127.0.0.1";
type Theme = "light" | "dark";
type ToastKind = "success" | "error" | "info";
type StatusFilter = "all" | "running" | "stopped";
type SortBy = "updated" | "name" | "port";
type SortOrder = "ascending" | "descending";
type ProjectView = "list" | "cards";
type ThemeEditorLevel = "basic" | "advanced";

type Project = {
  id: string;
  name: string;
  host: Host;
  port: number;
  command: string;
  createdAt: number;
  updatedAt: number;
  running: boolean;
  pid?: number;
  lastLog?: string;
  stopReason?: string;
};

type Toast = {
  id: string;
  kind: ToastKind;
  title: string;
  description: string;
};

type ApiError = {
  error?: string;
};

type PortAvailability = {
  available: boolean;
  reason?: string;
  suggestedPort?: number;
};

type PortFeedback = {
  kind: "success" | "error" | "checking";
  message: string;
};

type AddProjectDraft = {
  name: string;
  port: string;
  command: string;
  isEditingFormCommand: boolean;
  suggestedPort: number | null;
  portFeedback: PortFeedback | null;
  error: string;
  syncedCommandPort: number | null;
};

type StopAllResult = {
  projects: Project[];
  stoppedIds: string[];
  forcedIds: string[];
  errors: string[];
};

type ThemeColors = {
  background: string;
  surface: string;
  input: string;
  border: string;
  text: string;
  muted: string;
  primary: string;
  success: string;
  danger: string;
  open: string;
};

type CustomTheme = {
  id: string;
  name: string;
  mode: Theme;
  colors: ThemeColors;
  createdAt: number;
  updatedAt: number;
};

type SelectedThemeIds = Record<Theme, string>;

type ThemePreset = {
  id: string;
  name: string;
  mode: Theme;
  colors: ThemeColors;
};

type FilterSelectOption<T extends string> = {
  value: T;
  label: string;
};

type FilterSelectProps<T extends string> = {
  id: string;
  label: string;
  value: T;
  options: FilterSelectOption<T>[];
  onChange: (value: T) => void;
};

const API_BASE = "http://127.0.0.1:10001";
const LEGACY_STORAGE_KEY = "control-module-projects-v1";
const IMPORTED_KEY = "control-module-projects-imported-v2";
const THEME_KEY = "control-module-theme";
const CUSTOM_THEMES_KEY = "control-module-custom-themes-v1";
const SELECTED_THEMES_KEY = "control-module-selected-themes-v1";
const PROJECT_VIEW_KEY = "control-module-project-view";
const SCROLL_POSITION_KEY = "control-module-scroll-position";
const RUNNER_TOKEN_KEY = "control-module-runner-token";
const PRIMARY_HOST: Host = "127.0.0.1";
const ACTION_RATE_LIMIT_MS = 1000;
const DEFAULT_THEME_ID = "default";
const DEFAULT_SELECTED_THEMES: SelectedThemeIds = {
  light: DEFAULT_THEME_ID,
  dark: DEFAULT_THEME_ID,
};
const THEME_COLOR_FIELDS: Array<{ key: keyof ThemeColors; label: string }> = [
  { key: "background", label: "Background" },
  { key: "surface", label: "Surface" },
  { key: "input", label: "Input" },
  { key: "border", label: "Border" },
  { key: "text", label: "Text" },
  { key: "muted", label: "Muted text" },
  { key: "primary", label: "Primary" },
  { key: "success", label: "Start / success" },
  { key: "danger", label: "Stop / error" },
  { key: "open", label: "Open link" },
];
const DEFAULT_THEME_COLORS: Record<Theme, ThemeColors> = {
  dark: {
    background: "#111111",
    surface: "#191919",
    input: "#141414",
    border: "#333333",
    text: "#f2f2f2",
    muted: "#a0a0a0",
    primary: "#ededed",
    success: "#287a42",
    danger: "#b63b35",
    open: "#2764c7",
  },
  light: {
    background: "#f3f3f1",
    surface: "#ffffff",
    input: "#fafafa",
    border: "#d4d4d0",
    text: "#171717",
    muted: "#62625f",
    primary: "#202020",
    success: "#23733a",
    danger: "#b42318",
    open: "#1f5fb9",
  },
};
const THEME_PRESETS: Record<Theme, ThemePreset[]> = {
  dark: [
    {
      id: "preset-ocean",
      name: "Ocean",
      mode: "dark",
      colors: {
        background: "#0d141b",
        surface: "#14202a",
        input: "#101a23",
        border: "#2a3d4d",
        text: "#eaf2f8",
        muted: "#9bafbd",
        primary: "#dbeaf5",
        success: "#3d9d65",
        danger: "#d65c52",
        open: "#4c91d7",
      },
    },
    {
      id: "preset-forest",
      name: "Forest",
      mode: "dark",
      colors: {
        background: "#0f1510",
        surface: "#182019",
        input: "#131a14",
        border: "#304032",
        text: "#eef4ed",
        muted: "#a3b1a2",
        primary: "#dce8dc",
        success: "#399052",
        danger: "#d06156",
        open: "#5791c4",
      },
    },
    {
      id: "preset-teal",
      name: "Teal",
      mode: "dark",
      colors: {
        background: "#0d1515",
        surface: "#152222",
        input: "#111b1b",
        border: "#2b4443",
        text: "#ebf5f4",
        muted: "#9fb8b6",
        primary: "#d8ecea",
        success: "#33906a",
        danger: "#ce5e55",
        open: "#3f9899",
      },
    },
    {
      id: "preset-violet",
      name: "Violet",
      mode: "dark",
      colors: {
        background: "#151117",
        surface: "#201a23",
        input: "#19141c",
        border: "#44364b",
        text: "#f3edf5",
        muted: "#b2a2ba",
        primary: "#e6d9eb",
        success: "#4d9c66",
        danger: "#d45e57",
        open: "#9670d3",
      },
    },
    {
      id: "preset-rose",
      name: "Rose",
      mode: "dark",
      colors: {
        background: "#171013",
        surface: "#22181c",
        input: "#1c1417",
        border: "#4a3039",
        text: "#f7edf0",
        muted: "#bba1aa",
        primary: "#edd9df",
        success: "#4b9862",
        danger: "#d65b68",
        open: "#bf6887",
      },
    },
    {
      id: "preset-amber",
      name: "Amber",
      mode: "dark",
      colors: {
        background: "#17130d",
        surface: "#231d13",
        input: "#1c170f",
        border: "#493b25",
        text: "#f7f0e3",
        muted: "#bead91",
        primary: "#f0dfbf",
        success: "#5c9b55",
        danger: "#d15e4d",
        open: "#c18432",
      },
    },
    {
      id: "preset-slate",
      name: "Slate",
      mode: "dark",
      colors: {
        background: "#101216",
        surface: "#181b21",
        input: "#14171c",
        border: "#343943",
        text: "#eff2f6",
        muted: "#a2aab5",
        primary: "#dfe4ea",
        success: "#3d9660",
        danger: "#cf5b55",
        open: "#5b8fd6",
      },
    },
  ],
  light: [
    {
      id: "preset-ocean",
      name: "Ocean",
      mode: "light",
      colors: {
        background: "#eef3f8",
        surface: "#ffffff",
        input: "#f5f8fb",
        border: "#c9d6e2",
        text: "#12202d",
        muted: "#566777",
        primary: "#153b5c",
        success: "#217044",
        danger: "#b2352c",
        open: "#1769aa",
      },
    },
    {
      id: "preset-forest",
      name: "Forest",
      mode: "light",
      colors: {
        background: "#f1f4ef",
        surface: "#ffffff",
        input: "#f7f9f5",
        border: "#ccd6c8",
        text: "#19241a",
        muted: "#5c6b5d",
        primary: "#213b27",
        success: "#27733b",
        danger: "#a83b32",
        open: "#376fa3",
      },
    },
    {
      id: "preset-teal",
      name: "Teal",
      mode: "light",
      colors: {
        background: "#edf5f4",
        surface: "#ffffff",
        input: "#f5faf9",
        border: "#c6dbd8",
        text: "#162927",
        muted: "#566f6c",
        primary: "#244b47",
        success: "#287854",
        danger: "#ad3e36",
        open: "#237f82",
      },
    },
    {
      id: "preset-violet",
      name: "Violet",
      mode: "light",
      colors: {
        background: "#f4f1f7",
        surface: "#ffffff",
        input: "#faf7fc",
        border: "#d8cee0",
        text: "#251b2c",
        muted: "#6c5c75",
        primary: "#442555",
        success: "#347449",
        danger: "#ad3e38",
        open: "#7250b5",
      },
    },
    {
      id: "preset-rose",
      name: "Rose",
      mode: "light",
      colors: {
        background: "#f8f0f2",
        surface: "#ffffff",
        input: "#fcf6f8",
        border: "#e2cdd3",
        text: "#301e24",
        muted: "#796069",
        primary: "#5d2b3a",
        success: "#367849",
        danger: "#b43d49",
        open: "#a44869",
      },
    },
    {
      id: "preset-amber",
      name: "Amber",
      mode: "light",
      colors: {
        background: "#f7f2e8",
        surface: "#fffdfa",
        input: "#fbf7ef",
        border: "#dfd2ba",
        text: "#2c2418",
        muted: "#76664e",
        primary: "#5a431f",
        success: "#3f7a42",
        danger: "#aa3d32",
        open: "#9b6420",
      },
    },
    {
      id: "preset-slate",
      name: "Slate",
      mode: "light",
      colors: {
        background: "#f0f2f5",
        surface: "#ffffff",
        input: "#f7f8fa",
        border: "#cfd4dc",
        text: "#1d232b",
        muted: "#606a77",
        primary: "#2f3945",
        success: "#2e7948",
        danger: "#ad3933",
        open: "#366db5",
      },
    },
  ],
};
const CUSTOM_THEME_PROPERTIES = [
  "--bg",
  "--surface",
  "--input",
  "--border",
  "--border-strong",
  "--text",
  "--muted",
  "--faint",
  "--button",
  "--button-text",
  "--error",
  "--error-bg",
  "--success",
  "--success-bg",
  "--start-bg",
  "--start-hover",
  "--start-text",
  "--stop-bg",
  "--stop-hover",
  "--stop-text",
  "--open-bg",
  "--open-hover",
  "--open-text",
  "--action-text",
];
const HEX_COLOR_PATTERN = /^#[0-9a-f]{6}$/i;

function getBuiltInTheme(mode: Theme, themeId: string): ThemePreset | undefined {
  if (themeId === DEFAULT_THEME_ID) {
    return {
      id: DEFAULT_THEME_ID,
      name: "Default",
      mode,
      colors: DEFAULT_THEME_COLORS[mode],
    };
  }
  return THEME_PRESETS[mode].find((preset) => preset.id === themeId);
}

function themeIdIsAvailable(mode: Theme, themeId: string, customThemes: CustomTheme[]) {
  return Boolean(
    getBuiltInTheme(mode, themeId)
    || customThemes.some((item) => item.id === themeId && item.mode === mode),
  );
}

function hexToRgb(hex: string) {
  const value = hex.slice(1);
  return {
    r: Number.parseInt(value.slice(0, 2), 16),
    g: Number.parseInt(value.slice(2, 4), 16),
    b: Number.parseInt(value.slice(4, 6), 16),
  };
}

function rgbToHex(red: number, green: number, blue: number) {
  return `#${[red, green, blue]
    .map((value) => Math.round(value).toString(16).padStart(2, "0"))
    .join("")}`;
}

function mixHex(from: string, to: string, amount: number) {
  const start = hexToRgb(from);
  const end = hexToRgb(to);
  return rgbToHex(
    start.r + (end.r - start.r) * amount,
    start.g + (end.g - start.g) * amount,
    start.b + (end.b - start.b) * amount,
  );
}

function relativeLuminance(hex: string) {
  const { r, g, b } = hexToRgb(hex);
  const channels = [r, g, b].map((channel) => {
    const value = channel / 255;
    return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
  });
  return (channels[0] * 0.2126) + (channels[1] * 0.7152) + (channels[2] * 0.0722);
}

function contrastRatio(first: string, second: string) {
  const light = Math.max(relativeLuminance(first), relativeLuminance(second));
  const dark = Math.min(relativeLuminance(first), relativeLuminance(second));
  return (light + 0.05) / (dark + 0.05);
}

function contrastText(background: string) {
  return contrastRatio(background, "#ffffff") >= contrastRatio(background, "#111111")
    ? "#ffffff"
    : "#111111";
}

function ensureTextContrast(foreground: string, background: string, minimum = 4.5) {
  if (contrastRatio(foreground, background) >= minimum) return foreground;
  const target = contrastText(background);
  for (let amount = 0.05; amount <= 1; amount += 0.05) {
    const candidate = mixHex(foreground, target, amount);
    if (contrastRatio(candidate, background) >= minimum) return candidate;
  }
  return target;
}

function getThemeContrastError(colors: ThemeColors) {
  const surfaces: Array<[string, string]> = [
    ["background", colors.background],
    ["surface", colors.surface],
    ["input", colors.input],
  ];
  for (const [label, background] of surfaces) {
    if (contrastRatio(colors.text, background) < 4.5) {
      return `Text needs at least 4.5:1 contrast against the ${label} color.`;
    }
    if (contrastRatio(colors.muted, background) < 4.5) {
      return `Muted text needs at least 4.5:1 contrast against the ${label} color.`;
    }
  }
  return "";
}

function isThemeColors(value: unknown): value is ThemeColors {
  if (!value || typeof value !== "object") return false;
  const candidate = value as Record<string, unknown>;
  return THEME_COLOR_FIELDS.every(({ key }) => (
    typeof candidate[key] === "string" && HEX_COLOR_PATTERN.test(candidate[key] as string)
  ));
}

function isCustomTheme(value: unknown): value is CustomTheme {
  if (!value || typeof value !== "object") return false;
  const candidate = value as Partial<CustomTheme>;
  return typeof candidate.id === "string"
    && typeof candidate.name === "string"
    && (candidate.mode === "light" || candidate.mode === "dark")
    && isThemeColors(candidate.colors)
    && typeof candidate.createdAt === "number"
    && typeof candidate.updatedAt === "number";
}

function applyThemePreference(
  mode: Theme,
  selectedThemeIds: SelectedThemeIds,
  customThemes: CustomTheme[],
) {
  const root = document.documentElement;
  root.dataset.theme = mode;
  CUSTOM_THEME_PROPERTIES.forEach((property) => root.style.removeProperty(property));

  if (selectedThemeIds[mode] === DEFAULT_THEME_ID) return;

  const selected = customThemes.find((item) => (
    item.id === selectedThemeIds[mode] && item.mode === mode
  )) || getBuiltInTheme(mode, selectedThemeIds[mode]);
  if (!selected) return;

  const colors = selected.colors;
  const statusMix = mode === "dark" ? 0.18 : 0.12;
  const successText = ensureTextContrast(colors.success, colors.background);
  const errorText = ensureTextContrast(colors.danger, colors.background);
  const startText = contrastText(colors.success);
  const stopText = contrastText(colors.danger);
  const openText = contrastText(colors.open);
  const properties: Record<string, string> = {
    "--bg": colors.background,
    "--surface": colors.surface,
    "--input": colors.input,
    "--border": colors.border,
    "--border-strong": mixHex(colors.border, colors.text, 0.34),
    "--text": ensureTextContrast(colors.text, colors.background),
    "--muted": ensureTextContrast(colors.muted, colors.background),
    "--faint": ensureTextContrast(mixHex(colors.muted, colors.background, 0.25), colors.background),
    "--button": colors.primary,
    "--button-text": contrastText(colors.primary),
    "--error": errorText,
    "--error-bg": mixHex(colors.background, colors.danger, statusMix),
    "--success": successText,
    "--success-bg": mixHex(colors.background, colors.success, statusMix),
    "--start-bg": colors.success,
    "--start-hover": mixHex(colors.success, startText, 0.14),
    "--start-text": startText,
    "--stop-bg": colors.danger,
    "--stop-hover": mixHex(colors.danger, stopText, 0.14),
    "--stop-text": stopText,
    "--open-bg": colors.open,
    "--open-hover": mixHex(colors.open, openText, 0.14),
    "--open-text": openText,
    "--action-text": startText,
  };
  Object.entries(properties).forEach(([property, value]) => root.style.setProperty(property, value));
}

function getUrl(host: Host, port: number | string) {
  return `http://${host}:${port}`;
}

function replaceCommandPort(command: string, oldPort: number, newPort: number) {
  return command.replace(new RegExp(`\\b${oldPort}\\b`, "g"), String(newPort));
}

function commandHasPort(command: string, port: number) {
  return new RegExp(`\\b${port}\\b`).test(command);
}

function getLocalAddressLabel(port: number | string) {
  return `localhost:${port} & 127.0.0.1:${port}`;
}

function getAddedDetails(createdAt: number) {
  const addedDate = new Date(createdAt);
  const date = new Intl.DateTimeFormat(undefined, {
    weekday: "long",
    year: "numeric",
    month: "long",
    day: "numeric",
  }).format(addedDate);
  const time = new Intl.DateTimeFormat(undefined, {
    hour: "numeric",
    minute: "2-digit",
    timeZoneName: "short",
  }).format(addedDate);
  const days = Math.max(0, Math.floor((Date.now() - createdAt) / 86_400_000));
  return {
    date,
    time,
    elapsed: days === 0 ? "Today" : `${days} day${days === 1 ? "" : "s"}`,
  };
}

function getErrorMessage(error: unknown, fallback: string) {
  if (!(error instanceof Error)) return fallback;
  if (error.message === "Failed to fetch" || error.message.includes("NetworkError")) {
    return "The command runner is offline. Reopen Control Module.app and try again.";
  }
  return error.message || fallback;
}

function initializeRunnerSession() {
  const url = new URL(window.location.href);
  const fragment = new URLSearchParams(url.hash.replace(/^#/, ""));
  const tokenFromLauncher = fragment.get("token")?.trim() || "";
  if (tokenFromLauncher) {
    window.sessionStorage.setItem(RUNNER_TOKEN_KEY, tokenFromLauncher);
    url.hash = "";
    window.history.replaceState(window.history.state, "", `${url.pathname}${url.search}`);
  }
}

function getRunnerToken() {
  const token = window.sessionStorage.getItem(RUNNER_TOKEN_KEY)?.trim() || "";
  if (!token) {
    throw new Error("Open Control Module with its launcher to create a private local session.");
  }
  return token;
}

async function apiRequest<T>(path: string, options?: RequestInit): Promise<T> {
  const response = await fetch(`${API_BASE}${path}`, {
    ...options,
    cache: "no-store",
    headers: {
      ...(options?.body ? { "Content-Type": "application/json" } : {}),
      "X-Control-Token": getRunnerToken(),
      ...options?.headers,
    },
  });
  const data = (await response.json()) as T & ApiError;
  if (!response.ok) throw new Error(data.error || "The command runner could not complete that action.");
  return data;
}

function FilterSelect<T extends string,>({
  id,
  label,
  value,
  options,
  onChange,
}: FilterSelectProps<T>) {
  const [open, setOpen] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const optionRefs = useRef<Array<HTMLButtonElement | null>>([]);
  const selectedIndex = Math.max(0, options.findIndex((option) => option.value === value));
  const selectedOption = options[selectedIndex];
  const labelId = `${id}-label`;
  const listboxId = `${id}-options`;

  useEffect(() => {
    if (!open) return;
    function closeOutside(event: PointerEvent) {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false);
    }
    document.addEventListener("pointerdown", closeOutside);
    return () => document.removeEventListener("pointerdown", closeOutside);
  }, [open]);

  function focusOption(index: number) {
    window.requestAnimationFrame(() => optionRefs.current[index]?.focus());
  }

  function openFromKeyboard(index: number) {
    setOpen(true);
    focusOption(index);
  }

  function handleTriggerKeyDown(event: ReactKeyboardEvent<HTMLButtonElement>) {
    if (event.key === "ArrowDown") {
      event.preventDefault();
      openFromKeyboard(selectedIndex);
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      openFromKeyboard(selectedIndex);
    }
  }

  function handleOptionKeyDown(
    event: ReactKeyboardEvent<HTMLButtonElement>,
    index: number,
  ) {
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      const offset = event.key === "ArrowDown" ? 1 : -1;
      focusOption((index + offset + options.length) % options.length);
    } else if (event.key === "Home" || event.key === "End") {
      event.preventDefault();
      focusOption(event.key === "Home" ? 0 : options.length - 1);
    } else if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      setOpen(false);
      triggerRef.current?.focus();
    }
  }

  function chooseOption(option: FilterSelectOption<T>) {
    onChange(option.value);
    setOpen(false);
    triggerRef.current?.focus();
  }

  return (
    <div className="field compact-field filter-select" ref={rootRef}>
      <span className="filter-select-label" id={labelId}>{label}</span>
      <button
        className={`filter-select-trigger ${open ? "open" : ""}`}
        id={id}
        ref={triggerRef}
        type="button"
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-controls={listboxId}
        aria-labelledby={`${labelId} ${id}-value`}
        onClick={() => setOpen((current) => !current)}
        onKeyDown={handleTriggerKeyDown}
      >
        <span id={`${id}-value`}>{selectedOption.label}</span>
        <span className="filter-select-chevron" aria-hidden="true" />
      </button>
      {open && (
        <div className="filter-select-menu" id={listboxId} role="listbox" aria-labelledby={labelId}>
          {options.map((option, index) => {
            const selected = option.value === value;
            return (
              <button
                className={`filter-select-option ${selected ? "selected" : ""}`}
                key={option.value}
                ref={(element) => { optionRefs.current[index] = element; }}
                type="button"
                role="option"
                aria-selected={selected}
                tabIndex={selected ? 0 : -1}
                onClick={() => chooseOption(option)}
                onKeyDown={(event) => handleOptionKeyDown(event, index)}
              >
                <span>{option.label}</span>
                {selected && <span className="filter-select-check" aria-hidden="true">✓</span>}
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}

export default function Home() {
  const [name, setName] = useState("");
  const [port, setPort] = useState("");
  const [command, setCommand] = useState("");
  const [editingId, setEditingId] = useState<string | null>(null);
  const [isEditingName, setIsEditingName] = useState(false);
  const [isEditingFormCommand, setIsEditingFormCommand] = useState(true);
  const [projects, setProjects] = useState<Project[]>([]);
  const [isReady, setIsReady] = useState(false);
  const [runnerOnline, setRunnerOnline] = useState(false);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [restartingIds, setRestartingIds] = useState<Record<string, boolean>>({});
  const [projectToDelete, setProjectToDelete] = useState<Project | null>(null);
  const [deleteConfirmation, setDeleteConfirmation] = useState("");
  const [theme, setTheme] = useState<Theme>("dark");
  const [customThemes, setCustomThemes] = useState<CustomTheme[]>([]);
  const [selectedThemeIds, setSelectedThemeIds] = useState<SelectedThemeIds>(DEFAULT_SELECTED_THEMES);
  const [themeEditorOpen, setThemeEditorOpen] = useState(false);
  const [themeEditorMode, setThemeEditorMode] = useState<Theme>("dark");
  const [themeEditorLevel, setThemeEditorLevel] = useState<ThemeEditorLevel>("basic");
  const [editingThemeId, setEditingThemeId] = useState<string | null>(DEFAULT_THEME_ID);
  const [themeName, setThemeName] = useState("");
  const [themeColors, setThemeColors] = useState<ThemeColors>(DEFAULT_THEME_COLORS.dark);
  const [themeEditorError, setThemeEditorError] = useState("");
  const [confirmThemeDelete, setConfirmThemeDelete] = useState(false);
  const [themePreferencesLoaded, setThemePreferencesLoaded] = useState(false);
  const [error, setError] = useState("");
  const [portFeedback, setPortFeedback] = useState<PortFeedback | null>(null);
  const [suggestedPort, setSuggestedPort] = useState<number | null>(null);
  const [visibleCommands, setVisibleCommands] = useState<Record<string, boolean>>({});
  const [portSearch, setPortSearch] = useState("");
  const [filtersOpen, setFiltersOpen] = useState(false);
  const [projectInfoId, setProjectInfoId] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState<StatusFilter>("all");
  const [sortBy, setSortBy] = useState<SortBy>("updated");
  const [sortOrder, setSortOrder] = useState<SortOrder>("descending");
  const [projectView, setProjectView] = useState<ProjectView>("list");
  const [selectionMode, setSelectionMode] = useState(false);
  const [selectedProjectIds, setSelectedProjectIds] = useState<Record<string, boolean>>({});
  const [stopAllOpen, setStopAllOpen] = useState(false);
  const [restartPromptProject, setRestartPromptProject] = useState<Project | null>(null);
  const [isStartingAll, setIsStartingAll] = useState(false);
  const [isStoppingAll, setIsStoppingAll] = useState(false);
  const [actionCooldownActive, setActionCooldownActive] = useState(false);
  const [toasts, setToasts] = useState<Toast[]>([]);
  const statusSnapshot = useRef<Record<string, boolean>>({});
  const expectedStops = useRef<Set<string>>(new Set());
  const runnerWasOnline = useRef<boolean | null>(null);
  const filterMenuRef = useRef<HTMLDivElement>(null);
  const portCheckSequence = useRef(0);
  const syncedCommandPort = useRef<number | null>(null);
  const suspendedAddDraft = useRef<AddProjectDraft | null>(null);
  const projectWindows = useRef<Record<string, Window | null>>({});
  const restartTriggerRef = useRef<HTMLButtonElement | null>(null);
  const lastActionAt = useRef(0);
  const actionCooldownTimer = useRef<number | null>(null);
  const scrollRestored = useRef(false);
  const pendingScrollPosition = useRef<number | null>(null);
  const dialogReturnFocusRef = useRef<HTMLElement | null>(null);

  const editingProject = editingId
    ? projects.find((project) => project.id === editingId) || null
    : null;
  const editingProjectIsRunning = Boolean(editingProject?.running);
  const numericPort = Number(port);
  const validPort = /^\d{4}$/.test(port) && numericPort >= 1026 && numericPort <= 9999;
  const commandPortSynced = validPort
    && Boolean(command.trim())
    && commandHasPort(command, numericPort);
  const commandPortMismatch = validPort && Boolean(command.trim()) && !commandPortSynced;
  const addDraft = editingId && suspendedAddDraft.current
    ? suspendedAddDraft.current
    : {
        name,
        port,
        command,
        isEditingFormCommand,
        suggestedPort,
        portFeedback,
        error,
        syncedCommandPort: syncedCommandPort.current,
      };
  const addNumericPort = Number(addDraft.port);
  const addValidPort = /^\d{4}$/.test(addDraft.port)
    && addNumericPort >= 1026
    && addNumericPort <= 9999;
  const addCommandPortSynced = addValidPort
    && Boolean(addDraft.command.trim())
    && commandHasPort(addDraft.command, addNumericPort);
  const portConfirmedAvailable = portFeedback?.kind === "success" && suggestedPort === null;
  const formFieldsComplete = Boolean(name.trim() && port && command.trim());
  const canSubmitProject = editingProjectIsRunning
    ? Boolean(name.trim() && runnerOnline && !actionCooldownActive)
    : formFieldsComplete
      && validPort
      && commandPortSynced
      && portConfirmedAvailable
      && runnerOnline
      && !actionCooldownActive;
  const submitDisabledReason = !name.trim()
    ? "Enter a project name."
    : editingProjectIsRunning
      ? !runnerOnline
        ? "The command runner is offline."
        : actionCooldownActive
          ? "Please wait before saving again."
          : ""
      : !port
      ? "Enter a port."
      : !validPort
        ? "Use a port from 1026 to 9999."
        : !command.trim()
          ? "Enter a command."
          : !commandPortSynced
            ? `The command must include port ${numericPort}.`
            : portFeedback?.kind === "checking"
              ? "Wait for the port check to finish."
              : !portConfirmedAvailable
                ? "Choose an available port."
                : !runnerOnline
                  ? "The command runner is offline."
                  : actionCooldownActive
                    ? "Please wait before saving again."
                    : "";
  const deleteNameMatches = Boolean(
    projectToDelete && deleteConfirmation === projectToDelete.name,
  );

  const dismissToast = useCallback((id: string) => {
    setToasts((current) => current.filter((toast) => toast.id !== id));
  }, []);

  const notify = useCallback((kind: ToastKind, title: string, description: string) => {
    const id = crypto.randomUUID();
    setToasts((current) => [{ id, kind, title, description }, ...current]);
    if (kind !== "error") {
      window.setTimeout(() => {
        setToasts((current) => current.filter((toast) => toast.id !== id));
      }, 2500);
    }
  }, []);

  const beginRateLimitedAction = useCallback(() => {
    const now = Date.now();
    const remaining = ACTION_RATE_LIMIT_MS - (now - lastActionAt.current);
    if (remaining > 0) {
      notify("info", "Please wait", "Actions are limited to once per second.");
      return false;
    }

    lastActionAt.current = now;
    setActionCooldownActive(true);
    if (actionCooldownTimer.current) window.clearTimeout(actionCooldownTimer.current);
    actionCooldownTimer.current = window.setTimeout(() => {
      setActionCooldownActive(false);
      actionCooldownTimer.current = null;
    }, ACTION_RATE_LIMIT_MS);
    return true;
  }, [notify]);

  const loadProjects = useCallback(async (showError = false) => {
    try {
      const data = await apiRequest<{ projects: Project[] }>("/api/projects");

      if (Object.keys(statusSnapshot.current).length > 0) {
        for (const project of data.projects) {
          if (statusSnapshot.current[project.id] && !project.running) {
            if (expectedStops.current.has(project.id)) {
              expectedStops.current.delete(project.id);
            } else if (project.stopReason) {
              notify("info", `${project.name} stopped`, project.stopReason);
            } else {
              notify(
                "error",
                `${project.name} stopped`,
                project.lastLog || "The command exited. Check it and try again.",
              );
            }
          }
        }
      }

      statusSnapshot.current = Object.fromEntries(
        data.projects.map((project) => [project.id, project.running]),
      );
      setProjects(data.projects);
      setRunnerOnline(true);
      if (runnerWasOnline.current === false) {
        notify("success", "Runner connected", "Start and Stop are available again.");
      }
      runnerWasOnline.current = true;
      return data.projects;
    } catch (requestError) {
      const detail = getErrorMessage(requestError, "The command runner is offline.");
      setRunnerOnline(false);
      if (runnerWasOnline.current !== false) notify("error", "Runner offline", detail);
      runnerWasOnline.current = false;
      if (showError) setError(detail);
      return null;
    }
  }, [notify]);

  useEffect(() => {
    const savedTheme = window.localStorage.getItem(THEME_KEY) as Theme | null;
    const nextTheme = savedTheme === "light" || savedTheme === "dark"
      ? savedTheme
      : window.matchMedia("(prefers-color-scheme: light)").matches
        ? "light"
        : "dark";

    let nextCustomThemes: CustomTheme[] = [];
    let nextSelectedThemeIds = DEFAULT_SELECTED_THEMES;
    try {
      const storedCustomThemes = JSON.parse(
        window.localStorage.getItem(CUSTOM_THEMES_KEY) || "[]",
      ) as unknown;
      if (Array.isArray(storedCustomThemes)) {
        nextCustomThemes = storedCustomThemes.filter(isCustomTheme);
      }
    } catch {
      nextCustomThemes = [];
    }
    try {
      const storedSelections = JSON.parse(
        window.localStorage.getItem(SELECTED_THEMES_KEY) || "{}",
      ) as Partial<SelectedThemeIds>;
      nextSelectedThemeIds = {
        light: typeof storedSelections.light === "string"
          ? storedSelections.light
          : DEFAULT_THEME_ID,
        dark: typeof storedSelections.dark === "string"
          ? storedSelections.dark
          : DEFAULT_THEME_ID,
      };
    } catch {
      nextSelectedThemeIds = DEFAULT_SELECTED_THEMES;
    }
    nextSelectedThemeIds = {
      light: themeIdIsAvailable("light", nextSelectedThemeIds.light, nextCustomThemes)
        ? nextSelectedThemeIds.light
        : DEFAULT_THEME_ID,
      dark: themeIdIsAvailable("dark", nextSelectedThemeIds.dark, nextCustomThemes)
        ? nextSelectedThemeIds.dark
        : DEFAULT_THEME_ID,
    };

    setTheme(nextTheme);
    setCustomThemes(nextCustomThemes);
    setSelectedThemeIds(nextSelectedThemeIds);
    applyThemePreference(nextTheme, nextSelectedThemeIds, nextCustomThemes);
    setThemePreferencesLoaded(true);

    const savedProjectView = window.localStorage.getItem(PROJECT_VIEW_KEY);
    if (savedProjectView === "list" || savedProjectView === "cards") {
      setProjectView(savedProjectView);
    }
  }, []);

  useEffect(() => {
    if (!themePreferencesLoaded) return;
    window.localStorage.setItem(THEME_KEY, theme);
    window.localStorage.setItem(CUSTOM_THEMES_KEY, JSON.stringify(customThemes));
    window.localStorage.setItem(SELECTED_THEMES_KEY, JSON.stringify(selectedThemeIds));
    applyThemePreference(theme, selectedThemeIds, customThemes);
  }, [customThemes, selectedThemeIds, theme, themePreferencesLoaded]);

  useEffect(() => {
    const previousScrollRestoration = window.history.scrollRestoration;
    window.history.scrollRestoration = "manual";
    const storedPosition = Number(window.sessionStorage.getItem(SCROLL_POSITION_KEY));
    pendingScrollPosition.current = Number.isFinite(storedPosition) ? storedPosition : 0;
    let frameId: number | null = null;

    function saveScrollPosition() {
      window.sessionStorage.setItem(SCROLL_POSITION_KEY, String(Math.round(window.scrollY)));
    }

    function saveScrollPositionSoon() {
      if (frameId !== null) return;
      frameId = window.requestAnimationFrame(() => {
        frameId = null;
        saveScrollPosition();
      });
    }

    window.addEventListener("scroll", saveScrollPositionSoon, { passive: true });
    window.addEventListener("pagehide", saveScrollPosition);
    return () => {
      if (frameId !== null) window.cancelAnimationFrame(frameId);
      saveScrollPosition();
      window.removeEventListener("scroll", saveScrollPositionSoon);
      window.removeEventListener("pagehide", saveScrollPosition);
      window.history.scrollRestoration = previousScrollRestoration;
    };
  }, []);

  useLayoutEffect(() => {
    if (!isReady || scrollRestored.current) return;
    scrollRestored.current = true;
    const savedPosition = pendingScrollPosition.current
      ?? Number(window.sessionStorage.getItem(SCROLL_POSITION_KEY));
    if (!Number.isFinite(savedPosition) || savedPosition <= 0) return;
    window.scrollTo({ top: savedPosition, left: 0, behavior: "auto" });
  }, [isReady]);

  useEffect(() => {
    return () => {
      if (actionCooldownTimer.current) window.clearTimeout(actionCooldownTimer.current);
    };
  }, []);

  useEffect(() => {
    function rememberFocus(event: FocusEvent) {
      if (!document.querySelector('[role="dialog"]') && event.target instanceof HTMLElement) {
        dialogReturnFocusRef.current = event.target;
      }
    }
    document.addEventListener("focusin", rememberFocus);
    return () => document.removeEventListener("focusin", rememberFocus);
  }, []);

  const modalDialogOpen = Boolean(
    projectToDelete || stopAllOpen || projectInfoId || editingId || themeEditorOpen || restartPromptProject,
  );

  useEffect(() => {
    if (!modalDialogOpen) return;
    const background = Array.from(document.querySelectorAll<HTMLElement>("main > header, main > section"));
    const previousState = background.map((element) => ({
      element,
      inert: element.inert,
      ariaHidden: element.getAttribute("aria-hidden"),
    }));
    background.forEach((element) => {
      element.inert = true;
      element.setAttribute("aria-hidden", "true");
    });

    function trapFocus(event: KeyboardEvent) {
      if (event.key !== "Tab") return;
      const dialog = document.querySelector<HTMLElement>('[role="dialog"]');
      if (!dialog) return;
      const focusable = Array.from(dialog.querySelectorAll<HTMLElement>(
        'button:not([disabled]), a[href], input:not([disabled]), textarea:not([disabled]), select:not([disabled]), [tabindex]:not([tabindex="-1"])',
      )).filter((element) => !element.hidden && element.getClientRects().length > 0);
      if (focusable.length === 0) {
        event.preventDefault();
        dialog.focus();
        return;
      }
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    }

    document.addEventListener("keydown", trapFocus);
    return () => {
      document.removeEventListener("keydown", trapFocus);
      previousState.forEach(({ element, inert, ariaHidden }) => {
        element.inert = inert;
        if (ariaHidden === null) element.removeAttribute("aria-hidden");
        else element.setAttribute("aria-hidden", ariaHidden);
      });
      window.requestAnimationFrame(() => dialogReturnFocusRef.current?.focus());
    };
  }, [modalDialogOpen]);

  useEffect(() => {
    async function initialize() {
      initializeRunnerSession();
      const remoteProjects = await loadProjects(true);
      if (!remoteProjects) {
        setIsReady(true);
        return;
      }

      const alreadyImported = window.localStorage.getItem(IMPORTED_KEY);
      const legacyProjects = window.localStorage.getItem(LEGACY_STORAGE_KEY);
      if (!alreadyImported && legacyProjects) {
        try {
          const parsed = JSON.parse(legacyProjects) as Array<Partial<Project>>;
          for (const project of parsed) {
            if (!project.id || !project.name || !project.host || !project.port) continue;
            await apiRequest("/api/projects/save", {
              method: "POST",
              body: JSON.stringify({
                id: project.id,
                name: project.name,
                host: project.host,
                port: project.port,
                command: project.command || "",
              }),
            });
          }
          window.localStorage.setItem(IMPORTED_KEY, "true");
          await loadProjects();
        } catch {
          notify("error", "Import failed", "Older shortcuts could not be imported.");
        }
      }
      setIsReady(true);
    }
    initialize();
  }, [loadProjects, notify]);

  useEffect(() => {
    if (!isReady) return;
    const interval = window.setInterval(() => {
      if (!document.hidden) void loadProjects();
    }, 5000);
    return () => window.clearInterval(interval);
  }, [isReady, loadProjects]);

  useEffect(() => {
    function refreshStatus() {
      void loadProjects();
    }
    function refreshWhenVisible() {
      if (!document.hidden) refreshStatus();
    }

    window.addEventListener("pageshow", refreshStatus);
    window.addEventListener("focus", refreshStatus);
    document.addEventListener("visibilitychange", refreshWhenVisible);
    return () => {
      window.removeEventListener("pageshow", refreshStatus);
      window.removeEventListener("focus", refreshStatus);
      document.removeEventListener("visibilitychange", refreshWhenVisible);
    };
  }, [loadProjects]);

  useEffect(() => {
    if (!projectToDelete && !stopAllOpen && !filtersOpen && !projectInfoId && !editingId && !themeEditorOpen && !restartPromptProject) return;
    function closeOnEscape(event: KeyboardEvent) {
      if (event.key === "Escape") {
        setProjectToDelete(null);
        setDeleteConfirmation("");
        if (!isStoppingAll) setStopAllOpen(false);
        setFiltersOpen(false);
        setProjectInfoId(null);
        setThemeEditorOpen(false);
        setConfirmThemeDelete(false);
        setThemeEditorError("");
        if (restartPromptProject) {
          setRestartPromptProject(null);
          window.requestAnimationFrame(() => restartTriggerRef.current?.focus());
        }
        if (editingId) resetForm();
      }
    }
    window.addEventListener("keydown", closeOnEscape);
    return () => window.removeEventListener("keydown", closeOnEscape);
  }, [editingId, filtersOpen, isStoppingAll, projectInfoId, projectToDelete, restartPromptProject, stopAllOpen, themeEditorOpen]);

  useEffect(() => {
    if (!filtersOpen) return;
    function closeFiltersOutside(event: PointerEvent) {
      if (!filterMenuRef.current?.contains(event.target as Node)) setFiltersOpen(false);
    }
    document.addEventListener("pointerdown", closeFiltersOutside);
    return () => document.removeEventListener("pointerdown", closeFiltersOutside);
  }, [filtersOpen]);

  useEffect(() => {
    if (!projectInfoId) return;
    function closeProjectInfoOutside(event: PointerEvent) {
      const target = event.target;
      if (target instanceof Element && target.closest("[data-project-info]")) return;
      setProjectInfoId(null);
    }
    document.addEventListener("pointerdown", closeProjectInfoOutside);
    return () => document.removeEventListener("pointerdown", closeProjectInfoOutside);
  }, [projectInfoId]);

  useEffect(() => {
    const checkId = ++portCheckSequence.current;
    setSuggestedPort(null);

    if (editingProjectIsRunning) {
      setPortFeedback(null);
      return;
    }

    if (!port) {
      setPortFeedback(null);
      return;
    }

    if (!validPort) {
      const message = /^\d+$/.test(port) && numericPort < 1026
        ? `Port ${numericPort} is reserved. Use 1026–9999.`
        : "Enter a four-digit port from 1026 to 9999.";
      setPortFeedback({ kind: "error", message });
      return;
    }

    setPortFeedback({ kind: "checking", message: `Checking port ${numericPort}…` });
    const timer = window.setTimeout(async () => {
      try {
        const availability = await apiRequest<PortAvailability>("/api/ports/check", {
          method: "POST",
          body: JSON.stringify({
            host: PRIMARY_HOST,
            port: numericPort,
            projectId: editingId || undefined,
          }),
        });
        if (checkId !== portCheckSequence.current) return;
        if (availability.available) {
          setSuggestedPort(null);
          setPortFeedback({ kind: "success", message: `Port ${numericPort} is available.` });
          return;
        }

        const reason = availability.reason || `Port ${numericPort} is unavailable.`;
        setSuggestedPort(availability.suggestedPort ?? null);
        setPortFeedback({
          kind: "error",
          message: availability.suggestedPort
            ? `${reason} Change the port or switch to ${availability.suggestedPort}.`
            : `${reason} Change the port.`,
        });
      } catch (requestError) {
        if (checkId !== portCheckSequence.current) return;
        setSuggestedPort(null);
        setPortFeedback({
          kind: "error",
          message: getErrorMessage(requestError, "The port could not be checked."),
        });
      }
    }, 350);

    return () => window.clearTimeout(timer);
  }, [editingId, editingProjectIsRunning, numericPort, port, validPort]);

  const sortedProjects = useMemo(() => {
    return [...projects].sort((a, b) => {
      let comparison = 0;
      if (sortBy === "name") comparison = a.name.localeCompare(b.name, undefined, { sensitivity: "base" });
      else if (sortBy === "port") comparison = a.port - b.port;
      else comparison = a.updatedAt - b.updatedAt;
      return sortOrder === "ascending" ? comparison : -comparison;
    });
  }, [projects, sortBy, sortOrder]);

  const filteredProjects = useMemo(
    () => sortedProjects.filter((project) => {
      if (portSearch && !String(project.port).includes(portSearch)) return false;
      if (statusFilter === "running" && !project.running) return false;
      if (statusFilter === "stopped" && project.running) return false;
      return true;
    }),
    [portSearch, sortedProjects, statusFilter],
  );

  const selectedProjects = projects.filter((project) => selectedProjectIds[project.id]);
  const selectedCount = selectedProjects.length;
  const batchProjects = selectionMode ? selectedProjects : projects;
  const startableCount = batchProjects.filter((project) => !project.running).length;
  const stoppableCount = batchProjects.filter((project) => project.running).length;
  const activeFilterCount = Number(statusFilter !== "all")
    + Number(sortBy !== "updated" || sortOrder !== "descending");
  const hasProjectFilters = Boolean(portSearch || activeFilterCount);

  const themeEditorThemes = customThemes.filter((item) => item.mode === themeEditorMode);
  const basicThemeChoices = [
    getBuiltInTheme(themeEditorMode, DEFAULT_THEME_ID)!,
    ...THEME_PRESETS[themeEditorMode],
  ];
  const editingCustomTheme = editingThemeId
    ? themeEditorThemes.find((item) => item.id === editingThemeId)
    : null;
  const selectedThemeIsCustom = Boolean(
    themeEditorThemes.some((item) => item.id === selectedThemeIds[themeEditorMode]),
  );
  const themeColorsValid = THEME_COLOR_FIELDS.every(({ key }) => (
    HEX_COLOR_PATTERN.test(themeColors[key])
  ));
  const themeContrastError = themeColorsValid ? getThemeContrastError(themeColors) : "";
  const previewThemeColors = themeColorsValid
    ? themeColors
    : DEFAULT_THEME_COLORS[themeEditorMode];

  function loadThemeIntoEditor(mode: Theme, themeId: string, selectTheme = false) {
    const saved = customThemes.find((item) => item.id === themeId && item.mode === mode);
    const builtIn = getBuiltInTheme(mode, themeId);
    const selected = saved || builtIn || getBuiltInTheme(mode, DEFAULT_THEME_ID)!;
    setThemeEditorMode(mode);
    setEditingThemeId(selected.id);
    setThemeName(saved?.name || (selected.id === DEFAULT_THEME_ID ? "" : `${selected.name} custom`));
    setThemeColors(selected.colors);
    setThemeEditorError("");
    setConfirmThemeDelete(false);
    if (selectTheme) {
      setSelectedThemeIds((current) => ({ ...current, [mode]: selected.id }));
    }
  }

  function openThemeEditor() {
    loadThemeIntoEditor(theme, selectedThemeIds[theme]);
    setThemeEditorLevel("basic");
    setThemeEditorOpen(true);
  }

  function closeThemeEditor() {
    setThemeEditorOpen(false);
    setThemeEditorError("");
    setConfirmThemeDelete(false);
  }

  function changeThemeEditorMode(mode: Theme) {
    setTheme(mode);
    loadThemeIntoEditor(mode, selectedThemeIds[mode]);
  }

  function chooseSavedTheme(themeId: string) {
    loadThemeIntoEditor(themeEditorMode, themeId, true);
  }

  function chooseBasicTheme(themeId: string) {
    loadThemeIntoEditor(themeEditorMode, themeId, true);
  }

  function beginNewTheme() {
    setEditingThemeId(null);
    setThemeName("");
    setThemeEditorError("");
    setConfirmThemeDelete(false);
  }

  function updateThemeColor(key: keyof ThemeColors, value: string) {
    setThemeColors((current) => ({ ...current, [key]: value.toLowerCase() }));
    setThemeEditorError("");
  }

  function saveCustomTheme(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const trimmedName = themeName.trim();
    if (!trimmedName) {
      setThemeEditorError("Enter a theme name.");
      return;
    }
    if (!themeColorsValid) {
      setThemeEditorError("Use six-digit hex colors, such as #1f5fb9.");
      return;
    }
    if (themeContrastError) {
      setThemeEditorError(themeContrastError);
      return;
    }

    const now = Date.now();
    const existing = editingCustomTheme;
    const savedTheme: CustomTheme = {
      id: existing?.id || crypto.randomUUID(),
      name: trimmedName,
      mode: themeEditorMode,
      colors: themeColors,
      createdAt: existing?.createdAt || now,
      updatedAt: now,
    };
    setCustomThemes((current) => existing
      ? current.map((item) => item.id === existing.id ? savedTheme : item)
      : [...current, savedTheme]);
    setSelectedThemeIds((current) => ({ ...current, [themeEditorMode]: savedTheme.id }));
    setEditingThemeId(savedTheme.id);
    setThemeName(savedTheme.name);
    setThemeEditorError("");
    setConfirmThemeDelete(false);
    notify(
      "success",
      "Theme saved",
      `${savedTheme.name} is selected for ${themeEditorMode} mode.`,
    );
  }

  function deleteCustomTheme() {
    if (!editingCustomTheme) return;
    if (!confirmThemeDelete) {
      setConfirmThemeDelete(true);
      return;
    }
    const deleted = editingCustomTheme;
    setCustomThemes((current) => current.filter((item) => item.id !== editingThemeId));
    setSelectedThemeIds((current) => ({ ...current, [themeEditorMode]: DEFAULT_THEME_ID }));
    setEditingThemeId(DEFAULT_THEME_ID);
    setThemeName("");
    setThemeColors(DEFAULT_THEME_COLORS[themeEditorMode]);
    setConfirmThemeDelete(false);
    notify(
      "success",
      "Theme deleted",
      `${deleted?.name || "The theme"} was removed. ${themeEditorMode === "light" ? "Light" : "Dark"} mode now uses Default.`,
    );
  }

  function toggleTheme() {
    const nextTheme: Theme = theme === "dark" ? "light" : "dark";
    setTheme(nextTheme);
  }

  function toggleFormCommandEditing() {
    setIsEditingFormCommand((current) => !current);
  }

  function changeProjectView(nextView: ProjectView) {
    setProjectView(nextView);
    setFiltersOpen(false);
    window.localStorage.setItem(PROJECT_VIEW_KEY, nextView);
  }

  async function checkPort(portToCheck: number) {
    return apiRequest<PortAvailability>("/api/ports/check", {
      method: "POST",
      body: JSON.stringify({
        host: PRIMARY_HOST,
        port: portToCheck,
        projectId: editingId || undefined,
      }),
    });
  }

  function switchToSuggestedPort() {
    if (suggestedPort === null) return;

    const oldPort = numericPort;
    const newPort = suggestedPort;
    portCheckSequence.current += 1;
    setPort(String(newPort));
    setCommand((current) => {
      const updated = replaceCommandPort(current, oldPort, newPort);
      syncedCommandPort.current = newPort;
      return updated;
    });
    setSuggestedPort(null);
    setPortFeedback({
      kind: "checking",
      message: `Checking port ${newPort}…`,
    });
    setError("");
  }

  function resetForm() {
    const restoredDraft = editingId ? suspendedAddDraft.current : null;
    portCheckSequence.current += 1;
    syncedCommandPort.current = restoredDraft?.syncedCommandPort ?? null;
    setName(restoredDraft?.name ?? "");
    setPort(restoredDraft?.port ?? "");
    setCommand(restoredDraft?.command ?? "");
    setEditingId(null);
    setIsEditingName(false);
    setIsEditingFormCommand(restoredDraft?.isEditingFormCommand ?? true);
    setSuggestedPort(restoredDraft?.suggestedPort ?? null);
    setPortFeedback(restoredDraft?.portFeedback ?? null);
    setError(restoredDraft?.error ?? "");
    suspendedAddDraft.current = null;
  }

  function validate() {
    if (!name.trim()) {
      setError("Enter a project name.");
      notify("error", "Missing name", "Enter a project name.");
      return false;
    }
    if (editingProjectIsRunning) {
      setError("");
      return true;
    }
    if (!validPort) {
      setError("Enter a port from 1026 to 9999. Lower ports are reserved.");
      notify("error", "Invalid port", "Use a port from 1026 to 9999.");
      return false;
    }
    if (!command.trim()) {
      setError("Enter a project command.");
      notify("error", "Missing command", "Enter the command used to start the project.");
      return false;
    }
    if (!commandHasPort(command, numericPort)) {
      const detail = `The command must include port ${numericPort} to match the Port field.`;
      setError(detail);
      notify("error", "Port mismatch", detail);
      return false;
    }
    if (!portConfirmedAvailable) {
      const detail = portFeedback?.kind === "checking"
        ? "Wait for the port availability check to finish."
        : "Choose a port that is confirmed available.";
      setError(detail);
      notify("error", "Port not ready", detail);
      return false;
    }
    if (command.length > 4096) {
      setError("The command is too long.");
      notify("error", "Command too long", "Keep it under 4,096 characters.");
      return false;
    }
    setError("");
    return true;
  }

  async function saveProject(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!validate()) return;
    if (!beginRateLimitedAction()) return;

    const id = editingId || crypto.randomUUID();
    const projectName = name.trim();
    const checkId = ++portCheckSequence.current;
    const selectedPort = numericPort;
    const selectedCommand = command.trim();

    try {
      if (!editingProjectIsRunning) {
        const availability = await checkPort(selectedPort);
        if (checkId !== portCheckSequence.current) return;
        if (!availability.available) {
          const reason = availability.reason || `Port ${selectedPort} is unavailable.`;
          const detail = availability.suggestedPort
            ? `${reason} Change the port or switch to ${availability.suggestedPort}.`
            : `${reason} Change the port.`;
          setSuggestedPort(availability.suggestedPort ?? null);
          setPortFeedback({ kind: "error", message: detail });
          setError(reason);
          notify("error", "Port unavailable", detail);
          return;
        }
        setSuggestedPort(null);
      }

      await apiRequest("/api/projects/save", {
        method: "POST",
        body: JSON.stringify({
          id,
          name: projectName,
          host: PRIMARY_HOST,
          port: selectedPort,
          command: selectedCommand,
        }),
      });
      await loadProjects();
      const updated = Boolean(editingId);
      resetForm();
      notify("success", updated ? "Project updated" : "Project saved", projectName);
    } catch (requestError) {
      const detail = getErrorMessage(requestError, "The project could not be saved.");
      setError(detail);
      notify("error", "Save failed", detail);
    }
  }

  function editProject(project: Project) {
    suspendedAddDraft.current = {
      name,
      port,
      command,
      isEditingFormCommand,
      suggestedPort,
      portFeedback,
      error,
      syncedCommandPort: syncedCommandPort.current,
    };
    portCheckSequence.current += 1;
    syncedCommandPort.current = project.port;
    setName(project.name);
    setPort(String(project.port));
    setCommand(project.command);
    setEditingId(project.id);
    setIsEditingName(false);
    setIsEditingFormCommand(!project.command.trim());
    setSuggestedPort(null);
    setPortFeedback(null);
    setError("");
    setProjectInfoId(null);
  }

  function openDeleteModal(project: Project) {
    setDeleteConfirmation("");
    setProjectToDelete(project);
  }

  function closeDeleteModal() {
    setProjectToDelete(null);
    setDeleteConfirmation("");
  }

  async function copyCommand(project: Project) {
    if (!project.command) return;
    try {
      await navigator.clipboard.writeText(project.command);
      notify("info", "Command copied", project.name);
    } catch {
      notify("error", "Copy failed", "The command could not be copied.");
    }
  }

  function toggleCommandVisibility(projectId: string) {
    setVisibleCommands((current) => ({
      ...current,
      [projectId]: !current[projectId],
    }));
  }

  function projectWindowName(projectId: string) {
    return `control-module-project-${projectId}`;
  }

  function openProject(project: Project) {
    const projectWindow = window.open(
      getUrl(PRIMARY_HOST, project.port),
      projectWindowName(project.id),
    );
    if (!projectWindow) {
      notify("error", "Open blocked", "Allow popups for Control Module and try again.");
      return null;
    }
    projectWindows.current[project.id] = projectWindow;
    projectWindow.focus();
    return projectWindow;
  }

  async function refreshProjectAfterRestart(project: Project) {
    const projectUrl = getUrl(PRIMARY_HOST, project.port);
    try {
      await fetch(projectUrl, { cache: "reload", mode: "no-cors" });
    } catch {
      // The host restart still succeeded; opening it remains available below.
    }

    const existingWindow = projectWindows.current[project.id];
    if (existingWindow && !existingWindow.closed) {
      const freshUrl = new URL(projectUrl);
      freshUrl.searchParams.set("_control_reload", String(Date.now()));
      try {
        existingWindow.location.href = freshUrl.toString();
      } catch {
        // Cross-origin restrictions can block controlling an existing tab.
      }
    }
  }

  function closeRestartPrompt() {
    setRestartPromptProject(null);
    window.requestAnimationFrame(() => restartTriggerRef.current?.focus());
  }

  function acceptRestartPrompt() {
    if (!restartPromptProject) return;
    const opened = openProject(restartPromptProject);
    if (opened) setRestartPromptProject(null);
  }

  async function startProject(project: Project) {
    if (!project.command) {
      editProject(project);
      setError("Add a command before starting this project.");
      notify("error", "No command", "Add a command before starting this project.");
      return;
    }
    if (!beginRateLimitedAction()) return;
    setBusyId(project.id);
    setError("");
    try {
      const result = await apiRequest<{ project: Project }>("/api/projects/start", {
        method: "POST",
        body: JSON.stringify({ id: project.id }),
      });
      setProjects((current) => current.map((item) => item.id === project.id ? result.project : item));
      const refreshed = await loadProjects();
      const activeProject = refreshed?.find((item) => item.id === project.id) || result.project;
      if (!activeProject?.running) {
        throw new Error(activeProject?.lastLog || "The command exited before it started.");
      }
      const activeUrl = getUrl(PRIMARY_HOST, activeProject.port);
      notify("success", "Started", `${project.name} — ${activeUrl}`);
    } catch (requestError) {
      const detail = getErrorMessage(requestError, "The command could not start.");
      setError(detail);
      notify("error", `Could not start ${project.name}`, detail);
    } finally {
      setBusyId(null);
    }
  }

  async function stopProject(project: Project) {
    if (!beginRateLimitedAction()) return;
    setBusyId(project.id);
    setError("");
    expectedStops.current.add(project.id);
    try {
      const result = await apiRequest<{ project: Project }>("/api/projects/stop", {
        method: "POST",
        body: JSON.stringify({ id: project.id }),
      });
      setProjects((current) => current.map((item) => item.id === project.id ? result.project : item));
      await loadProjects();
      expectedStops.current.delete(project.id);
      notify("success", "Stopped", project.name);
    } catch (requestError) {
      expectedStops.current.delete(project.id);
      const detail = getErrorMessage(requestError, "The command could not be stopped.");
      setError(detail);
      notify("error", `Could not stop ${project.name}`, detail);
    } finally {
      setBusyId(null);
    }
  }

  async function restartProject(project: Project, trigger?: HTMLButtonElement) {
    if (!project.running) {
      notify("info", "Project is stopped", `Start ${project.name} before restarting it.`);
      return;
    }
    if (!beginRateLimitedAction()) return;
    restartTriggerRef.current = trigger || null;
    setRestartPromptProject(null);
    setBusyId(project.id);
    setRestartingIds((current) => ({ ...current, [project.id]: true }));
    setError("");
    expectedStops.current.add(project.id);
    try {
      const result = await apiRequest<{ project: Project }>("/api/projects/restart", {
        method: "POST",
        body: JSON.stringify({ id: project.id }),
      });
      setProjects((current) => current.map((item) => item.id === project.id ? result.project : item));
      const refreshed = await loadProjects();
      const activeProject = refreshed?.find((item) => item.id === project.id) || result.project;
      if (!activeProject?.running) {
        throw new Error(activeProject?.lastLog || "The command exited during restart.");
      }
      await refreshProjectAfterRestart(activeProject);
      setRestartPromptProject(activeProject);
    } catch (requestError) {
      const detail = getErrorMessage(requestError, "The command could not restart.");
      setError(detail);
      notify("error", `Could not restart ${project.name}`, detail);
      await loadProjects();
    } finally {
      expectedStops.current.delete(project.id);
      setRestartingIds((current) => {
        const next = { ...current };
        delete next[project.id];
        return next;
      });
      setBusyId(null);
    }
  }

  function clearProjectFilters() {
    setPortSearch("");
    setStatusFilter("all");
    setSortBy("updated");
    setSortOrder("descending");
    setFiltersOpen(false);
  }

  function toggleSelectionMode() {
    if (selectionMode) setSelectedProjectIds({});
    setSelectionMode((current) => !current);
  }

  function toggleProjectSelection(projectId: string) {
    setSelectedProjectIds((current) => ({
      ...current,
      [projectId]: !current[projectId],
    }));
  }

  async function runAllProjects() {
    const stoppedProjects = batchProjects.filter((project) => !project.running);
    if (stoppedProjects.length === 0) return;
    if (!beginRateLimitedAction()) return;

    setIsStartingAll(true);
    setError("");

    const results = await Promise.all(stoppedProjects.map(async (project) => {
      try {
        const result = await apiRequest<{ project: Project }>("/api/projects/start", {
          method: "POST",
          body: JSON.stringify({ id: project.id }),
        });
        return { project, started: result.project, error: "" };
      } catch (requestError) {
        return {
          project,
          started: null,
          error: getErrorMessage(requestError, "The command could not start."),
        };
      }
    }));

    try {
      const refreshed = await loadProjects();
      const latestProjects = refreshed || projects;
      const failures: string[] = [];
      let startedCount = 0;

      for (const result of results) {
        const activeProject = latestProjects.find((project) => project.id === result.project.id)
          || result.started;
        if (result.error || !activeProject?.running) {
          failures.push(`${result.project.name}: ${result.error || activeProject?.lastLog || "The command exited before it started."}`);
          continue;
        }

        startedCount += 1;
      }

      if (failures.length > 0) {
        const detail = failures.join(" ");
        setError(detail);
        notify(
          "error",
          selectionMode ? "Some selected projects could not start" : "Some projects could not start",
          `${startedCount} started, ${failures.length} failed. ${detail}`,
        );
      } else {
        notify(
          "success",
          selectionMode ? "Selected projects running" : "All projects running",
          `${startedCount} ${startedCount === 1 ? "project" : "projects"} started successfully.`,
        );
      }
    } finally {
      setIsStartingAll(false);
    }
  }

  async function stopAllProjects() {
    const runningProjects = batchProjects.filter((project) => project.running);
    if (runningProjects.length === 0) {
      setStopAllOpen(false);
      return;
    }
    if (!beginRateLimitedAction()) return;

    setIsStoppingAll(true);
    setError("");
    for (const project of runningProjects) expectedStops.current.add(project.id);

    try {
      let result: StopAllResult;
      if (selectionMode) {
        const stopResults = await Promise.all(runningProjects.map(async (project) => {
          try {
            await apiRequest<{ project: Project }>("/api/projects/stop", {
              method: "POST",
              body: JSON.stringify({ id: project.id }),
            });
            return { project, error: "" };
          } catch (requestError) {
            return {
              project,
              error: getErrorMessage(requestError, "The command could not be stopped."),
            };
          }
        }));
        const refreshed = await loadProjects();
        result = {
          projects: refreshed || projects,
          stoppedIds: stopResults.filter((item) => !item.error).map((item) => item.project.id),
          forcedIds: [],
          errors: stopResults
            .filter((item) => item.error)
            .map((item) => `${item.project.name}: ${item.error}`),
        };
      } else {
        result = await apiRequest<StopAllResult>("/api/projects/stop-all", {
          method: "POST",
          body: JSON.stringify({}),
        });
        setProjects(result.projects);
        await loadProjects();
      }

      if (result.errors.length > 0) {
        const detail = result.errors.join(" ");
        setError(detail);
        notify(
          "error",
          selectionMode ? "Some selected projects could not stop" : "Some projects could not stop cleanly",
          detail,
        );
      } else {
        notify(
          "success",
          selectionMode ? "Selected projects stopped" : "All projects stopped",
          `${result.stoppedIds.length} managed ${result.stoppedIds.length === 1 ? "process" : "processes"} stopped.`,
        );
      }
      if (result.forcedIds.length > 0) {
        notify(
          "info",
          "Forced stop used",
          `${result.forcedIds.length} ${result.forcedIds.length === 1 ? "process needed" : "processes needed"} the last-resort stop after five seconds.`,
        );
      }
      setStopAllOpen(false);
    } catch (requestError) {
      const detail = getErrorMessage(requestError, "The projects could not be stopped.");
      setError(detail);
      notify("error", selectionMode ? "Stop selected failed" : "Stop all failed", detail);
    } finally {
      for (const project of runningProjects) expectedStops.current.delete(project.id);
      setIsStoppingAll(false);
    }
  }

  async function removeProject(project: Project) {
    if (!beginRateLimitedAction()) return;
    setBusyId(project.id);
    try {
      await apiRequest("/api/projects/delete", {
        method: "POST",
        body: JSON.stringify({ id: project.id }),
      });
      if (editingId === project.id) resetForm();
      await loadProjects();
      notify("success", "Deleted", project.name);
      closeDeleteModal();
    } catch (requestError) {
      const detail = getErrorMessage(requestError, "The project could not be deleted.");
      setError(detail);
      notify("error", "Delete failed", detail);
    } finally {
      setBusyId(null);
    }
  }

  function renderProjectForm() {
    return (
      <form className="project-form" onSubmit={saveProject} noValidate>
        {editingId ? (
          <div className="editing-name-field">
            <div className="editing-name-header">
              <span>Name</span>
              <button
                className="name-edit-button"
                type="button"
                onClick={() => setIsEditingName((current) => !current)}
              >
                {isEditingName ? "Done" : "Edit name"}
              </button>
            </div>
            {isEditingName ? (
              <input
                id="edit-project-name"
                value={name}
                onChange={(event) => {
                  setName(event.target.value);
                  setError("");
                }}
                maxLength={48}
                autoComplete="off"
                aria-label="Project name"
                autoFocus
              />
            ) : (
              <strong>{name}</strong>
            )}
          </div>
        ) : (
          <div className="field project-name-field">
            <label htmlFor="project-name">Name</label>
            <input
              id="project-name"
              value={name}
              onChange={(event) => {
                setName(event.target.value);
                setError("");
              }}
              placeholder="Name of project"
              maxLength={48}
              autoComplete="off"
            />
          </div>
        )}

        <div className={`address-fields port-only${editingProjectIsRunning ? " form-field-locked" : ""}`}>
          <div className="field port-field">
            <label htmlFor="edit-project-port">Port</label>
            <input
              id="edit-project-port"
              inputMode="numeric"
              pattern="[0-9]*"
              value={port}
              onChange={(event) => {
                portCheckSequence.current += 1;
                const nextPort = event.target.value.replace(/\D/g, "").slice(0, 4);
                const nextPortNumber = Number(nextPort);
                const trackedPort = syncedCommandPort.current;
                setPort(nextPort);
                if (
                  /^\d{4}$/.test(nextPort)
                  && trackedPort !== null
                  && trackedPort !== nextPortNumber
                  && commandHasPort(command, trackedPort)
                ) {
                  setCommand(replaceCommandPort(command, trackedPort, nextPortNumber));
                  syncedCommandPort.current = nextPortNumber;
                } else if (/^\d{4}$/.test(nextPort) && trackedPort === null) {
                  syncedCommandPort.current = nextPortNumber;
                }
                setSuggestedPort(null);
                setPortFeedback(null);
                setError("");
              }}
              placeholder="1234"
              maxLength={4}
              autoComplete="off"
              aria-invalid={portFeedback?.kind === "error"}
              aria-describedby={editingProjectIsRunning ? "running-edit-note" : undefined}
              disabled={editingProjectIsRunning}
            />
            {!editingProjectIsRunning && portFeedback && (
              <span className={`port-feedback ${portFeedback.kind}`} role="status">
                {portFeedback.message}
              </span>
            )}
          </div>
        </div>

        <div className={`field command-form-field${editingProjectIsRunning ? " form-field-locked" : ""}`}>
          <div className="command-form-header">
            <span>Command</span>
            <div className="command-form-header-actions">
              {command.trim() && !editingProjectIsRunning && (
                <button
                  className="command-edit-button"
                  type="button"
                  onClick={toggleFormCommandEditing}
                  aria-expanded={isEditingFormCommand}
                >
                  {!isEditingFormCommand && <span className="action-icon edit-icon" aria-hidden="true" />}
                  {isEditingFormCommand ? "Done" : "Edit"}
                </button>
              )}
            </div>
          </div>
          {isEditingFormCommand || !command.trim() ? (
            <textarea
              id="edit-project-command"
              className="command-editor"
              value={command}
              onChange={(event) => {
                const nextCommand = event.target.value;
                setCommand(nextCommand);
                setError("");
                if (validPort && commandHasPort(nextCommand, numericPort)) {
                  syncedCommandPort.current = numericPort;
                }
              }}
              onBlur={(event) => {
                if (!command.trim()) return;
                if (event.relatedTarget instanceof Element
                  && event.relatedTarget.closest(".command-form-field")) return;
                setIsEditingFormCommand(false);
              }}
              placeholder="the path to make your app run"
              rows={1}
              maxLength={4096}
              spellCheck={false}
              aria-label="Command"
              aria-invalid={commandPortMismatch}
              aria-describedby={editingProjectIsRunning ? "running-edit-note" : undefined}
              disabled={editingProjectIsRunning}
              autoFocus={Boolean(command) && !editingProjectIsRunning}
            />
          ) : (
            <div
              className="command-collapsed"
              title={command}
              aria-disabled={editingProjectIsRunning || undefined}
              aria-describedby={editingProjectIsRunning ? "running-edit-note" : undefined}
            >
              <code>{command}</code>
            </div>
          )}
          {!editingProjectIsRunning && validPort && command.trim() && (
            <span
              className={`command-sync-feedback ${commandPortSynced ? "success" : "error"}`}
              role="status"
            >
              {commandPortSynced
                ? `Command matches port ${numericPort}.`
                : `Command must include port ${numericPort} to match the Port field.`}
            </span>
          )}
        </div>

        {validPort && <code className="address-preview">{getLocalAddressLabel(numericPort)}</code>}
        {error && <p className="form-error" role="alert">{error}</p>}

        <div className="form-actions">
          {editingId && <button className="button" type="button" onClick={resetForm}>Cancel</button>}
          {suggestedPort !== null && (
            <button
              className="button port-suggestion-button"
              type="button"
              onClick={switchToSuggestedPort}
            >
              Switch to {suggestedPort}
            </button>
          )}
          <button
            className="button primary"
            type="submit"
            disabled={!canSubmitProject}
            title={submitDisabledReason || undefined}
          >
            {editingProjectIsRunning ? "Save name" : editingId ? "Save" : "Add"}
          </button>
        </div>
      </form>
    );
  }

  return (
    <main className="app-shell">
      {toasts.length > 0 && (
        <div
          className="toast-region"
          aria-label="Notifications"
          aria-live="polite"
          aria-relevant="additions removals"
        >
          {toasts.map((toast) => (
            <section
              className={`toast toast-${toast.kind}`}
              key={toast.id}
              role={toast.kind === "error" ? "alert" : "status"}
            >
              <span className="toast-icon" aria-hidden="true">
                {toast.kind === "success" ? "✓" : toast.kind === "error" ? "!" : "i"}
              </span>
              <div className="toast-copy">
                <strong>{toast.title}</strong>
                <p>{toast.description}</p>
              </div>
              {toast.kind === "error" ? (
                <button type="button" onClick={() => dismissToast(toast.id)} aria-label="Dismiss notification">×</button>
              ) : (
                <span className="toast-timer" aria-hidden="true" />
              )}
            </section>
          ))}
        </div>
      )}

      <header className="app-header">
        <h1>Control Module</h1>
        <div className="app-header-actions">
          <div className="header-bulk-actions" role="group" aria-label="Project actions">
            <button
              className={`button select-mode-button ${selectionMode ? "active" : ""}`}
              type="button"
              onClick={toggleSelectionMode}
              disabled={isStartingAll || isStoppingAll}
              aria-pressed={selectionMode}
            >
              {selectionMode ? (
                <>
                  Done
                  {selectedCount > 0 && <span className="header-selection-count"> ({selectedCount})</span>}
                </>
              ) : "Select"}
            </button>
            <button
              className="button run-all-button"
              type="button"
              onClick={() => void runAllProjects()}
              disabled={!runnerOnline || startableCount === 0 || isStartingAll || isStoppingAll || actionCooldownActive || Boolean(editingId)}
              aria-label={isStartingAll
                ? "Starting projects"
                : selectionMode ? "Run selected projects" : "Run all projects"}
              title={editingId
                ? "Finish editing before starting projects"
                : selectionMode && selectedCount === 0
                  ? "Select at least one project"
                  : startableCount === 0
                    ? selectionMode ? "The selected projects are already running" : "All projects are already running"
                    : selectionMode ? "Start the selected stopped projects" : "Start every stopped project"}
            >
              {isStartingAll ? "Starting…" : (
                <>Run<span className="header-action-scope">-{selectionMode ? "selected" : "all"}</span></>
              )}
            </button>
            <button
              className="button stop-all-button"
              type="button"
              onClick={() => setStopAllOpen(true)}
              disabled={!runnerOnline || stoppableCount === 0 || isStartingAll || isStoppingAll || actionCooldownActive}
              aria-label={selectionMode ? "Stop selected projects" : "Stop all projects"}
              title={selectionMode && selectedCount === 0
                ? "Select at least one project"
                : stoppableCount === 0
                  ? selectionMode ? "No selected projects are running" : "No projects are running"
                  : selectionMode ? "Stop the selected running projects" : "Stop every project started by Control Module"}
            >
              Stop<span className="header-action-scope">-{selectionMode ? "selected" : "all"}</span>
            </button>
          </div>
          <div className="header-appearance-actions" role="group" aria-label="Appearance">
            <button
              className="theme-button"
              type="button"
              onClick={openThemeEditor}
              aria-label="Open custom themes"
              title="Custom themes"
            >
              <span className="action-icon theme-settings-icon" aria-hidden="true" />
            </button>
            <button
              className="theme-button"
              type="button"
              onClick={toggleTheme}
              aria-label={theme === "dark" ? "Switch to light mode" : "Switch to dark mode"}
              title={theme === "dark" ? "Light mode" : "Dark mode"}
            >
              <span
                className={`action-icon ${theme === "dark" ? "sun-icon" : "moon-icon"}`}
                aria-hidden="true"
              />
            </button>
          </div>
        </div>
      </header>

      <section
        className="form-section"
        aria-labelledby="form-title"
        aria-hidden={editingId ? true : undefined}
        inert={editingId ? true : undefined}
      >
        <h2 id="form-title">Add project</h2>
        <form className="project-form" onSubmit={saveProject} noValidate>
          <div className="field project-name-field">
            <label htmlFor="project-name">Name</label>
            <input
              id="project-name"
              value={addDraft.name}
              onChange={(event) => {
                setName(event.target.value);
                setError("");
              }}
                placeholder="Name of project"
              maxLength={48}
              autoComplete="off"
            />
          </div>

          <div className="address-fields port-only">
            <div className="field port-field">
              <label htmlFor="add-project-port">Port</label>
              <input
                id="add-project-port"
                inputMode="numeric"
                pattern="[0-9]*"
                value={addDraft.port}
                onChange={(event) => {
                  portCheckSequence.current += 1;
                  const nextPort = event.target.value.replace(/\D/g, "").slice(0, 4);
                  const nextPortNumber = Number(nextPort);
                  const trackedPort = syncedCommandPort.current;
                  setPort(nextPort);
                  if (
                    /^\d{4}$/.test(nextPort)
                    && trackedPort !== null
                    && trackedPort !== nextPortNumber
                    && commandHasPort(command, trackedPort)
                  ) {
                    setCommand(replaceCommandPort(command, trackedPort, nextPortNumber));
                    syncedCommandPort.current = nextPortNumber;
                  } else if (/^\d{4}$/.test(nextPort) && trackedPort === null) {
                    syncedCommandPort.current = nextPortNumber;
                  }
                  setSuggestedPort(null);
                  setPortFeedback(null);
                  setError("");
                }}
                placeholder="1234"
                maxLength={4}
                autoComplete="off"
                aria-invalid={portFeedback?.kind === "error"}
              />
              {addDraft.portFeedback && (
                <span className={`port-feedback ${addDraft.portFeedback.kind}`} role="status">
                  {addDraft.portFeedback.message}
                </span>
              )}
            </div>
          </div>

          <div className="field command-form-field">
            <div className="command-form-header">
              <span>Command</span>
              <div className="command-form-header-actions">
                {addDraft.command.trim() && (
                  <button
                    className="command-edit-button"
                    type="button"
                    onClick={toggleFormCommandEditing}
                    aria-expanded={addDraft.isEditingFormCommand}
                  >
                    {!addDraft.isEditingFormCommand && <span className="action-icon edit-icon" aria-hidden="true" />}
                    {addDraft.isEditingFormCommand ? "Done" : "Edit"}
                  </button>
                )}
              </div>
            </div>
            {addDraft.isEditingFormCommand || !addDraft.command.trim() ? (
              <textarea
                id="add-project-command"
                className="command-editor"
                value={addDraft.command}
                onChange={(event) => {
                  const nextCommand = event.target.value;
                  setCommand(nextCommand);
                  setError("");
                  if (validPort && commandHasPort(nextCommand, numericPort)) {
                    syncedCommandPort.current = numericPort;
                  }
                }}
                onBlur={(event) => {
                  if (!command.trim()) return;
                  if (event.relatedTarget instanceof Element
                    && event.relatedTarget.closest(".command-form-field")) return;
                  setIsEditingFormCommand(false);
                }}
                placeholder="the path to make your app run"
                rows={1}
                maxLength={4096}
                spellCheck={false}
                aria-label="Command"
                aria-invalid={addValidPort && Boolean(addDraft.command.trim()) && !addCommandPortSynced}
                autoFocus={!editingId && Boolean(addDraft.command)}
              />
            ) : (
              <div className="command-collapsed" title={addDraft.command}>
                <code>{addDraft.command}</code>
              </div>
            )}
            {addValidPort && addDraft.command.trim() && (
              <span
                className={`command-sync-feedback ${addCommandPortSynced ? "success" : "error"}`}
                role="status"
              >
                {addCommandPortSynced
                  ? `Command matches port ${addNumericPort}.`
                  : `Command must include port ${addNumericPort} to match the Port field.`}
              </span>
            )}
          </div>

          {addValidPort && <code className="address-preview">{getLocalAddressLabel(addNumericPort)}</code>}
          {addDraft.error && <p className="form-error" role="alert">{addDraft.error}</p>}

          <div className="form-actions">
            {addDraft.suggestedPort !== null && (
              <button
                className="button port-suggestion-button"
                type="button"
                onClick={switchToSuggestedPort}
              >
                Switch to {addDraft.suggestedPort}
              </button>
            )}
            <button
              className="button primary"
              type="submit"
              disabled={Boolean(editingId) || !canSubmitProject}
              title={editingId ? "Close Edit project to use Add project." : submitDisabledReason || undefined}
            >
              Add
            </button>
          </div>
        </form>
      </section>

      <section className="projects-section" aria-labelledby="projects-title">
        <div className="section-header">
          <h2 id="projects-title">Projects</h2>
          <span>{hasProjectFilters ? `${filteredProjects.length}/${projects.length}` : projects.length}</span>
        </div>

        <div className="project-toolbar" ref={filterMenuRef}>
          <div className="port-search">
            <label className="sr-only" htmlFor="port-search">Search projects by port</label>
            <input
              id="port-search"
              inputMode="numeric"
              value={portSearch}
              onChange={(event) => setPortSearch(event.target.value.replace(/\D/g, "").slice(0, 4))}
              placeholder="Search port"
              autoComplete="off"
            />
          </div>
          <button
            className="button filter-button"
            type="button"
            onClick={() => setFiltersOpen((current) => !current)}
            aria-expanded={filtersOpen}
            aria-controls="project-filters"
          >
            <span className="action-icon filter-icon" aria-hidden="true" />
            Filters{activeFilterCount > 0 ? ` (${activeFilterCount})` : ""}
          </button>
          <div className="view-switch" role="group" aria-label="Project view">
            <button
              className={`view-switch-button ${projectView === "list" ? "active" : ""}`}
              type="button"
              onClick={() => changeProjectView("list")}
              aria-label="List view"
              aria-pressed={projectView === "list"}
              title="List view"
            >
              <span className="action-icon list-icon" aria-hidden="true" />
            </button>
            <button
              className={`view-switch-button ${projectView === "cards" ? "active" : ""}`}
              type="button"
              onClick={() => changeProjectView("cards")}
              aria-label="Card view"
              aria-pressed={projectView === "cards"}
              title="Card view"
            >
              <span className="action-icon cards-icon" aria-hidden="true" />
            </button>
          </div>
          {filtersOpen && (
            <div className="filter-popover" id="project-filters" role="region" aria-label="Project filters and sorting">
              <div className="filter-popover-header">
                <strong>Filters</strong>
                <button
                  className="filter-close-button"
                  type="button"
                  onClick={() => setFiltersOpen(false)}
                  aria-label="Close filters"
                >
                  <span className="action-icon close-icon" aria-hidden="true" />
                </button>
              </div>

              <div className="filter-popover-grid">
                <FilterSelect<StatusFilter>
                  id="status-filter"
                  label="Status"
                  value={statusFilter}
                  onChange={setStatusFilter}
                  options={[
                    { value: "all", label: "Running and stopped" },
                    { value: "running", label: "Running" },
                    { value: "stopped", label: "Stopped" },
                  ]}
                />
                <FilterSelect<SortBy>
                  id="sort-by"
                  label="Sort by"
                  value={sortBy}
                  onChange={setSortBy}
                  options={[
                    { value: "updated", label: "Last updated" },
                    { value: "name", label: "Name" },
                    { value: "port", label: "Port" },
                  ]}
                />
              </div>

              <fieldset className="sort-order-field">
                <legend>Order</legend>
                <div className="sort-order-buttons">
                  <button
                    className={`button ${sortOrder === "ascending" ? "active" : ""}`}
                    type="button"
                    onClick={() => setSortOrder("ascending")}
                    aria-pressed={sortOrder === "ascending"}
                  >
                    <span className="action-icon sort-ascending-icon" aria-hidden="true" />
                    Ascending
                  </button>
                  <button
                    className={`button ${sortOrder === "descending" ? "active" : ""}`}
                    type="button"
                    onClick={() => setSortOrder("descending")}
                    aria-pressed={sortOrder === "descending"}
                  >
                    <span className="action-icon sort-descending-icon" aria-hidden="true" />
                    Descending
                  </button>
                </div>
              </fieldset>

              <div className="filter-popover-actions">
                <button className="button" type="button" onClick={clearProjectFilters}>
                  Clear all
                </button>
                <button className="button primary" type="button" onClick={() => setFiltersOpen(false)}>
                  Done
                </button>
              </div>
            </div>
          )}
        </div>

        {!isReady ? (
          <p className="empty-message">Loading…</p>
        ) : !runnerOnline ? (
          <p className="empty-message error-text">Runner offline. Reopen Control Module.app.</p>
        ) : sortedProjects.length === 0 ? (
          <p className="empty-message">No projects.</p>
        ) : filteredProjects.length === 0 ? (
          <p className="empty-message">No matching projects.</p>
        ) : (
          <div className={`project-list ${projectView === "cards" ? "card-view" : "list-view"}`}>
            {filteredProjects.map((project) => {
              const url = getUrl(PRIMARY_HOST, project.port);
              const localhostUrl = getUrl("localhost", project.port);
              const isRestarting = Boolean(restartingIds[project.id]);
              const isBusy = busyId === project.id || isRestarting;
              const isSelected = Boolean(selectedProjectIds[project.id]);
              const commandVisible = Boolean(visibleCommands[project.id]);
              const addedDetails = getAddedDetails(project.createdAt);
              return (
                <article className={`project-row ${selectionMode ? "selecting" : ""}`} key={project.id}>
                  <div className="project-main">
                    <div className="project-header-row">
                      <div className="project-heading">
                        <div className="project-heading-main">
                        {selectionMode && (
                          <button
                            className={`project-select-button ${isSelected ? "selected" : ""}`}
                            type="button"
                            onClick={() => toggleProjectSelection(project.id)}
                            aria-label={`${isSelected ? "Deselect" : "Select"} ${project.name}`}
                            aria-pressed={isSelected}
                          >
                            <span aria-hidden="true">✓</span>
                          </button>
                        )}
                        <div className="project-info-control" data-project-info>
                          <button
                            className="project-info-button"
                            type="button"
                            onClick={() => setProjectInfoId((current) => current === project.id ? null : project.id)}
                            aria-label={`Open menu for ${project.name}`}
                            aria-expanded={projectInfoId === project.id}
                            aria-controls={`project-menu-${project.id}`}
                            title="Project menu"
                          >
                            <span className="action-icon ellipsis-vertical-icon" aria-hidden="true" />
                          </button>
                          {projectInfoId === project.id && (
                            <div
                              className="project-menu"
                              id={`project-menu-${project.id}`}
                              role="menu"
                              aria-label={`${project.name} options`}
                            >
                              <div className="project-menu-submenu">
                                <button
                                  className="project-menu-item"
                                  type="button"
                                  role="menuitem"
                                  aria-haspopup="dialog"
                                >
                                  <span className="action-icon calendar-clock-icon" aria-hidden="true" />
                                  Date added
                                  <span className="action-icon chevron-right-icon project-menu-arrow" aria-hidden="true" />
                                </button>
                                <div
                                  className="project-date-popover"
                                  role="dialog"
                                  aria-label={`${project.name} added date`}
                                >
                                  <strong>Added</strong>
                                  <dl>
                                    <dt>Date</dt>
                                    <dd>{addedDetails.date}</dd>
                                    <dt>Time</dt>
                                    <dd>{addedDetails.time}</dd>
                                    <dt>Age</dt>
                                    <dd>{addedDetails.elapsed}</dd>
                                  </dl>
                                </div>
                              </div>
                            </div>
                          )}
                        </div>
                        <h3>{project.name}</h3>
                        <span className={`project-status ${project.running ? "running" : ""}`}>
                          {project.running ? "Running" : "Stopped"}
                        </span>
                      </div>
                      </div>
                      <div
                        className="project-quick-actions"
                        role="group"
                        aria-label={`${project.name} quick actions`}
                      >
                        <button
                          className="project-open-link project-edit-link"
                          type="button"
                          onClick={() => editProject(project)}
                          disabled={isBusy || isStartingAll || isStoppingAll}
                          aria-label={`Edit ${project.name}`}
                          title={project.running ? "Rename project; stop it to edit Port or Command" : "Edit project"}
                        >
                          <span className="action-icon edit-icon" aria-hidden="true" />
                          <span className="project-quick-action-label">Edit project</span>
                        </button>
                        {project.running ? (
                          <button
                            className="project-open-link project-open-action"
                            type="button"
                            onClick={() => openProject(project)}
                            aria-label={`Open ${project.name}`}
                            title="Open link"
                          >
                            <span className="action-icon external-link-icon" aria-hidden="true" />
                            <span className="project-quick-action-label">Open link</span>
                          </button>
                        ) : (
                          <button
                            className="project-open-link project-open-action disabled"
                            type="button"
                            disabled
                            aria-label={`Open ${project.name} (project is stopped)`}
                            title="Start the project to open its link"
                          >
                            <span className="action-icon external-link-icon" aria-hidden="true" />
                            <span className="project-quick-action-label">Open link</span>
                          </button>
                        )}
                      </div>
                    </div>
                    <div className="project-url">
                      {project.running ? (
                        <>
                          <a href={localhostUrl} target="_blank" rel="noreferrer">localhost:{project.port}</a>
                          <span aria-hidden="true">&amp;</span>
                          <a href={url} target="_blank" rel="noreferrer">127.0.0.1:{project.port}</a>
                        </>
                      ) : (
                        <span>{getLocalAddressLabel(project.port)}</span>
                      )}
                    </div>
                    <div className="project-command-layout">
                      <div className="project-command">
                        <div className="project-command-header">
                          <span>Command</span>
                          <div className="project-command-actions">
                            <button
                              className="command-action-button"
                              type="button"
                              onClick={() => toggleCommandVisibility(project.id)}
                              disabled={!project.command}
                              aria-label={`${commandVisible ? "Hide" : "Show"} ${project.name} command`}
                              aria-pressed={commandVisible}
                              title={commandVisible ? "Hide command" : "Show command"}
                            >
                              <span
                                className={`action-icon ${commandVisible ? "eye-off-icon" : "eye-icon"}`}
                                aria-hidden="true"
                              />
                            </button>
                            <button
                              className="command-action-button"
                              type="button"
                              onClick={() => copyCommand(project)}
                              disabled={!project.command}
                              aria-label={`Copy ${project.name} command`}
                              title="Copy command"
                            >
                              <span className="action-icon copy-icon" aria-hidden="true" />
                            </button>
                          </div>
                        </div>
                        <div className="project-command-body">
                          <code
                            className={project.command && !commandVisible ? "command-hidden" : ""}
                            tabIndex={commandVisible ? 0 : -1}
                            aria-label={project.command && !commandVisible
                              ? `${project.name} command hidden`
                              : undefined}
                          >
                            {project.command
                              ? commandVisible
                                ? project.command
                                : "\u00a0"
                              : "No command"}
                          </code>
                        </div>
                      </div>

                      <div className="project-actions">
                        <div className="project-runtime-actions">
                          <button
                            className={`button project-action-toggle ${project.running ? "stop" : "start"}`}
                            type="button"
                            onClick={() => project.running ? stopProject(project) : startProject(project)}
                            disabled={isBusy || isStartingAll || isStoppingAll || actionCooldownActive}
                          >
                            {isBusy ? "Wait…" : project.running ? "Stop" : "Start"}
                          </button>
                          <button
                            className="button project-action-restart"
                            type="button"
                            onClick={(event) => restartProject(project, event.currentTarget)}
                            disabled={!project.running || isBusy || isStartingAll || isStoppingAll || actionCooldownActive}
                            title={project.running ? `Restart ${project.name}` : "Start the project before restarting it"}
                            aria-busy={isRestarting}
                          >
                            {isRestarting && (
                              <span className="action-icon restart-loader-icon" aria-hidden="true" />
                            )}
                            {isRestarting ? "Restarting…" : "Restart"}
                          </button>
                        </div>
                        <button
                          className="button quiet-danger project-action-delete"
                          type="button"
                          onClick={() => openDeleteModal(project)}
                          disabled={isBusy || isStartingAll || isStoppingAll || actionCooldownActive}
                        >
                          Delete
                        </button>
                      </div>
                    </div>
                    {!project.running && project.lastLog && (
                      <div className="project-error" role="status">
                        <strong>Project error</strong>
                        <code>{project.lastLog}</code>
                      </div>
                    )}
                  </div>
                </article>
              );
            })}
          </div>
        )}
      </section>

      {restartPromptProject && (
        <div
          className="modal-backdrop"
          onMouseDown={(event) => {
            if (event.currentTarget === event.target) closeRestartPrompt();
          }}
        >
          <section
            className="delete-modal restart-open-modal"
            role="dialog"
            aria-modal="true"
            aria-labelledby="restart-open-title"
            aria-describedby="restart-open-description"
          >
            <h2 id="restart-open-title">Restart complete</h2>
            <p id="restart-open-description">
              {restartPromptProject.name} is running again and its page was refreshed.
              {" "}Do you want to go to the website?
            </p>
            <code className="restart-open-address">
              {getLocalAddressLabel(restartPromptProject.port)}
            </code>
            <div className="modal-actions">
              <button className="button" type="button" onClick={closeRestartPrompt} autoFocus>
                Deny
              </button>
              <button className="button open" type="button" onClick={acceptRestartPrompt}>
                Accept
              </button>
            </div>
          </section>
        </div>
      )}

      {themeEditorOpen && (
        <div
          className="modal-backdrop"
          onMouseDown={(event) => {
            if (event.currentTarget === event.target) closeThemeEditor();
          }}
        >
          <section
            className="edit-project-modal theme-modal"
            role="dialog"
            aria-modal="true"
            aria-labelledby="theme-editor-title"
          >
            <div className="edit-project-modal-header">
              <div>
                <h2 id="theme-editor-title">Themes</h2>
                <p className="theme-modal-note">Each mode keeps its own selected theme.</p>
              </div>
              <button
                className="filter-close-button"
                type="button"
                onClick={closeThemeEditor}
                aria-label="Close themes"
              >
                <span className="action-icon close-icon" aria-hidden="true" />
              </button>
            </div>

            <div className="theme-mode-tabs" aria-label="Theme mode">
              {(["light", "dark"] as Theme[]).map((mode) => (
                <button
                  className={themeEditorMode === mode ? "active" : ""}
                  type="button"
                  key={mode}
                  onClick={() => changeThemeEditorMode(mode)}
                  aria-pressed={themeEditorMode === mode}
                >
                  <span
                    className={`action-icon ${mode === "light" ? "sun-icon" : "moon-icon"}`}
                    aria-hidden="true"
                  />
                  {mode === "light" ? "Light" : "Dark"}
                </button>
              ))}
            </div>

            <div className="theme-editor-levels" aria-label="Theme options">
              {(["basic", "advanced"] as ThemeEditorLevel[]).map((level) => (
                <button
                  className={themeEditorLevel === level ? "active" : ""}
                  type="button"
                  key={level}
                  onClick={() => setThemeEditorLevel(level)}
                  aria-pressed={themeEditorLevel === level}
                >
                  {level === "basic" ? "Basic" : "Advanced"}
                </button>
              ))}
            </div>

            {themeEditorLevel === "basic" ? (
              <div className="theme-basic-panel">
                {selectedThemeIsCustom && (
                  <p className="theme-basic-note">
                    A custom theme is selected. Choose a preset below or use Advanced to edit it.
                  </p>
                )}
                <div className="theme-preset-grid">
                  {basicThemeChoices.map((preset) => {
                    const isSelected = selectedThemeIds[themeEditorMode] === preset.id;
                    const swatches: Array<keyof ThemeColors> = [
                      "background",
                      "surface",
                      "primary",
                      "success",
                      "danger",
                      "open",
                    ];
                    return (
                      <button
                        className={`theme-preset-button ${isSelected ? "selected" : ""}`}
                        type="button"
                        key={preset.id}
                        onClick={() => chooseBasicTheme(preset.id)}
                        aria-pressed={isSelected}
                      >
                        <span className="theme-preset-heading">
                          <strong>{preset.name}</strong>
                          {isSelected && <span>Selected</span>}
                        </span>
                        <span className="theme-preset-swatches" aria-hidden="true">
                          {swatches.map((color) => (
                            <span key={color} style={{ background: preset.colors[color] }} />
                          ))}
                        </span>
                      </button>
                    );
                  })}
                </div>
                <div className="modal-actions theme-basic-actions">
                  <button className="button" type="button" onClick={closeThemeEditor}>Close</button>
                </div>
              </div>
            ) : (
            <form className="theme-form" onSubmit={saveCustomTheme} noValidate>
              <div className="theme-library-row">
                <div className="field">
                  <label htmlFor="saved-theme">Saved theme</label>
                  <select
                    id="saved-theme"
                    value={editingThemeId || "new"}
                    onChange={(event) => chooseSavedTheme(event.target.value)}
                  >
                    {editingThemeId === null && <option value="new">New theme</option>}
                    <optgroup label="Built-in">
                      <option value={DEFAULT_THEME_ID}>Default</option>
                      {THEME_PRESETS[themeEditorMode].map((preset) => (
                        <option value={preset.id} key={preset.id}>{preset.name}</option>
                      ))}
                    </optgroup>
                    {themeEditorThemes.length > 0 && (
                      <optgroup label="Custom">
                        {themeEditorThemes.map((item) => (
                          <option value={item.id} key={item.id}>{item.name}</option>
                        ))}
                      </optgroup>
                    )}
                  </select>
                </div>
                <div className="theme-library-actions">
                  <button className="button" type="button" onClick={beginNewTheme}>
                    New
                  </button>
                  <button
                    className={`button ${confirmThemeDelete ? "delete-confirm" : "quiet-danger"}`}
                    type="button"
                    onClick={deleteCustomTheme}
                    disabled={!editingCustomTheme}
                  >
                    {confirmThemeDelete ? "Confirm delete" : "Delete"}
                  </button>
                </div>
              </div>

              <div className="field theme-name-field">
                <label htmlFor="theme-name">Name</label>
                <input
                  id="theme-name"
                  value={themeName}
                  onChange={(event) => {
                    setThemeName(event.target.value);
                    setThemeEditorError("");
                  }}
                  placeholder="Theme name"
                  maxLength={40}
                  autoComplete="off"
                />
              </div>

              <div className="theme-color-grid">
                {THEME_COLOR_FIELDS.map(({ key, label }) => {
                  const validColor = HEX_COLOR_PATTERN.test(themeColors[key]);
                  return (
                    <div className="field theme-color-field" key={key}>
                      <label htmlFor={`theme-color-${key}`}>{label}</label>
                      <div className="theme-color-control">
                        <input
                          className="theme-color-picker"
                          type="color"
                          value={validColor ? themeColors[key] : DEFAULT_THEME_COLORS[themeEditorMode][key]}
                          onChange={(event) => updateThemeColor(key, event.target.value)}
                          aria-label={`Choose ${label.toLowerCase()} color`}
                        />
                        <input
                          id={`theme-color-${key}`}
                          value={themeColors[key]}
                          onChange={(event) => updateThemeColor(key, event.target.value)}
                          maxLength={7}
                          spellCheck={false}
                          autoComplete="off"
                          aria-invalid={!validColor}
                        />
                      </div>
                    </div>
                  );
                })}
              </div>

              <div
                className="theme-preview"
                style={{
                  background: previewThemeColors.background,
                  borderColor: previewThemeColors.border,
                  color: previewThemeColors.text,
                }}
                aria-label="Theme preview"
              >
                <div
                  className="theme-preview-surface"
                  style={{
                    background: previewThemeColors.surface,
                    borderColor: previewThemeColors.border,
                  }}
                >
                  <strong>Preview</strong>
                  <span style={{ color: previewThemeColors.muted }}>Project controls</span>
                  <div>
                    <span
                      style={{
                        background: previewThemeColors.success,
                        color: contrastText(previewThemeColors.success),
                      }}
                    >Start</span>
                    <span
                      style={{
                        background: previewThemeColors.open,
                        color: contrastText(previewThemeColors.open),
                      }}
                    >Open</span>
                    <span
                      style={{
                        background: previewThemeColors.danger,
                        color: contrastText(previewThemeColors.danger),
                      }}
                    >Stop</span>
                  </div>
                </div>
              </div>

              {themeColorsValid && themeContrastError && (
                <div className="form-error" role="status">{themeContrastError}</div>
              )}
              {themeEditorError && <div className="form-error" role="alert">{themeEditorError}</div>}

              <div className="modal-actions theme-modal-actions">
                <button className="button" type="button" onClick={closeThemeEditor}>Cancel</button>
                <button
                  className="button primary"
                  type="submit"
                  disabled={!themeName.trim() || !themeColorsValid || Boolean(themeContrastError)}
                  title={themeContrastError || undefined}
                >
                  {editingCustomTheme ? "Save changes" : "Save theme"}
                </button>
              </div>
            </form>
            )}
          </section>
        </div>
      )}

      {editingId && (
        <div
          className="modal-backdrop"
          onMouseDown={(event) => {
            if (event.currentTarget === event.target) resetForm();
          }}
        >
          <section
            className="edit-project-modal"
            role="dialog"
            aria-modal="true"
            aria-labelledby="edit-project-title"
          >
            <div className="edit-project-modal-header">
              <div className="edit-project-modal-heading">
                <h2 id="edit-project-title">Edit project</h2>
                {editingProjectIsRunning && (
                  <p className="running-edit-note" id="running-edit-note">
                    Running · Stop to edit port or command.
                  </p>
                )}
              </div>
              <button
                className="filter-close-button"
                type="button"
                onClick={resetForm}
                aria-label="Close edit project"
                autoFocus
              >
                <span className="action-icon close-icon" aria-hidden="true" />
              </button>
            </div>
            {renderProjectForm()}
          </section>
        </div>
      )}

      {projectToDelete && (
        <div
          className="modal-backdrop"
          onMouseDown={(event) => {
            if (event.currentTarget === event.target) closeDeleteModal();
          }}
        >
          <section
            className="delete-modal"
            role="dialog"
            aria-modal="true"
            aria-labelledby="delete-title"
            aria-describedby="delete-description"
          >
            <h2 id="delete-title">Delete {projectToDelete.name}?</h2>
            <form
              onSubmit={(event) => {
                event.preventDefault();
                if (deleteNameMatches && busyId !== projectToDelete.id) {
                  void removeProject(projectToDelete);
                }
              }}
            >
              <p id="delete-description">
                Type the project name ({projectToDelete.name}) to confirm.
                {projectToDelete.running ? " Its running process will also stop." : ""}
              </p>
              <div className="field delete-confirmation-field">
                <label htmlFor="delete-project-name">Project name</label>
                <input
                  id="delete-project-name"
                  value={deleteConfirmation}
                  onChange={(event) => setDeleteConfirmation(event.target.value)}
                  placeholder={projectToDelete.name}
                  autoComplete="off"
                  spellCheck={false}
                  autoFocus
                />
              </div>
              <div className="modal-actions">
                <button className="button" type="button" onClick={closeDeleteModal}>
                  Cancel
                </button>
                <button
                  className="button delete-confirm"
                  type="submit"
                  disabled={!deleteNameMatches || busyId === projectToDelete.id || actionCooldownActive}
                >
                  {busyId === projectToDelete.id ? "Deleting…" : "Delete"}
                </button>
              </div>
            </form>
          </section>
        </div>
      )}

      {stopAllOpen && (
        <div
          className="modal-backdrop"
          onMouseDown={(event) => {
            if (event.currentTarget === event.target && !isStoppingAll) setStopAllOpen(false);
          }}
        >
          <section
            className="delete-modal stop-all-modal"
            role="dialog"
            aria-modal="true"
            aria-labelledby="stop-all-title"
            aria-describedby="stop-all-description"
          >
            <h2 id="stop-all-title">
              {selectionMode ? "Stop selected running projects?" : "Stop all running projects?"}
            </h2>
            <p id="stop-all-description">
              This stops {stoppableCount} {stoppableCount === 1 ? "project" : "projects"} started by Control Module.
            </p>
            <div className="stop-all-safety">
              Only managed project processes are included. Unrelated apps, system services, project files,
              and external databases are not touched. Each project receives a graceful shutdown request and
              five seconds to clean up before a last-resort forced stop.
            </div>
            <div className="modal-actions">
              <button
                className="button"
                type="button"
                onClick={() => setStopAllOpen(false)}
                disabled={isStoppingAll}
                autoFocus
              >
                Cancel
              </button>
              <button
                className="button delete-confirm"
                type="button"
                onClick={() => void stopAllProjects()}
                disabled={isStoppingAll || actionCooldownActive}
              >
                {isStoppingAll ? "Stopping…" : selectionMode ? "Stop selected" : "Stop all"}
              </button>
            </div>
          </section>
        </div>
      )}
    </main>
  );
}
