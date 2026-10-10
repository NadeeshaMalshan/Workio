import { vi } from 'vitest';

export function setupWorkerTestEnv() {
  if (typeof window !== 'undefined') {
    if (!window.IntersectionObserver) {
      window.IntersectionObserver = class {
        observe() {}
        unobserve() {}
        disconnect() {}
      };
    }
    if (window.HTMLElement && !window.HTMLElement.prototype.attachInternals) {
      window.HTMLElement.prototype.attachInternals = function() {
        return {
          setFormValue: () => {},
          setValidity: () => {},
          validationMessage: '',
          validity: { valid: true },
          willValidate: true,
          checkValidity: () => true,
          reportValidity: () => true,
        };
      };
    }
    if (window.ElementInternals && !window.ElementInternals.prototype.setFormValue) {
      window.ElementInternals.prototype.setFormValue = () => {};
      window.ElementInternals.prototype.setValidity = () => {};
    }
    if (!window.scrollTo) {
      window.scrollTo = vi.fn();
    }
  }
}

setupWorkerTestEnv();
