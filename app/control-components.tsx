"use client";

import type { KeyboardEvent } from "react";
import { useEffect, useRef, useState } from "react";

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

export function FilterSelect<T extends string>({
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

  function handleTriggerKeyDown(event: KeyboardEvent<HTMLButtonElement>) {
    if (event.key !== "ArrowDown" && event.key !== "ArrowUp") return;
    event.preventDefault();
    setOpen(true);
    focusOption(selectedIndex);
  }

  function handleOptionKeyDown(event: KeyboardEvent<HTMLButtonElement>, index: number) {
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

export type ToastKind = "success" | "error" | "info";
export type Toast = {
  id: string;
  kind: ToastKind;
  title: string;
  description: string;
};

export type ProcessCommandKind = "setup" | "start" | "stop" | "restart";

type ProcessCommandTabsProps = {
  active: ProcessCommandKind;
  commands: Record<ProcessCommandKind, { label: string; value: string }>;
  onChange: (kind: ProcessCommandKind) => void;
};

export function ProcessCommandTabs({ active, commands, onChange }: ProcessCommandTabsProps) {
  const kinds = Object.keys(commands) as ProcessCommandKind[];
  const tabRefs = useRef<Array<HTMLButtonElement | null>>([]);

  function chooseFromKeyboard(event: KeyboardEvent<HTMLButtonElement>, index: number) {
    let nextIndex = index;
    if (event.key === "ArrowRight" || event.key === "ArrowDown") nextIndex = (index + 1) % kinds.length;
    else if (event.key === "ArrowLeft" || event.key === "ArrowUp") nextIndex = (index - 1 + kinds.length) % kinds.length;
    else if (event.key === "Home") nextIndex = 0;
    else if (event.key === "End") nextIndex = kinds.length - 1;
    else return;
    event.preventDefault();
    onChange(kinds[nextIndex]);
    tabRefs.current[nextIndex]?.focus();
  }

  return (
    <div className="process-command-tabs" role="tablist" aria-label="Process command">
      {kinds.map((kind, index) => (
        <button
          key={kind}
          ref={(element) => { tabRefs.current[index] = element; }}
          id={`process-command-tab-${kind}`}
          className={active === kind ? "active" : ""}
          type="button"
          role="tab"
          aria-selected={active === kind}
          aria-controls="process-command-panel"
          tabIndex={active === kind ? 0 : -1}
          onClick={() => onChange(kind)}
          onKeyDown={(event) => chooseFromKeyboard(event, index)}
        >
          {commands[kind].label}
          {commands[kind].value.trim() && (
            <span className="process-command-set" aria-label="configured" />
          )}
        </button>
      ))}
    </div>
  );
}

export function ToastRegion({
  toasts,
  onDismiss,
}: {
  toasts: Toast[];
  onDismiss: (id: string) => void;
}) {
  if (toasts.length === 0) return null;
  return (
    <div className="toast-region" aria-label="Notifications" aria-relevant="additions removals">
      {toasts.map((toast) => (
        <section
          className={`toast toast-${toast.kind}`}
          key={toast.id}
          role={toast.kind === "error" ? "alert" : "status"}
          aria-atomic="true"
        >
          <span className="toast-icon" aria-hidden="true">
            {toast.kind === "success" ? "✓" : toast.kind === "error" ? "!" : "i"}
          </span>
          <div className="toast-copy">
            <strong>{toast.title}</strong>
            <p>{toast.description}</p>
          </div>
          {toast.kind === "error" ? (
            <button type="button" onClick={() => onDismiss(toast.id)} aria-label="Dismiss notification">×</button>
          ) : (
            <span className="toast-timer" aria-hidden="true" />
          )}
        </section>
      ))}
    </div>
  );
}
