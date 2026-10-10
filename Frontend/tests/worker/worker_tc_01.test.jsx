import { describe, it, expect } from 'vitest';
import { WORKER_SERVICES_CATALOG } from '../../src/data/workerServicesCatalog.js';

describe('Frontend Worker TC-01: Worker Services Catalog Definitions', () => {
  it('contains official service categories with required properties and default skills', () => {
    expect(WORKER_SERVICES_CATALOG).toBeDefined();
    expect(WORKER_SERVICES_CATALOG.length).toBeGreaterThanOrEqual(20);

    const categoryNames = WORKER_SERVICES_CATALOG.map(c => c.name);
    expect(categoryNames).toContain('Plumbing');
    expect(categoryNames).toContain('Electrical');
    expect(categoryNames).toContain('Carpentry');
    expect(categoryNames).toContain('Painting');

    const plumbing = WORKER_SERVICES_CATALOG.find(c => c.name === 'Plumbing');
    expect(plumbing.id).toBe('plumbing');
    expect(plumbing.icon).toBeTruthy();
    expect(Array.isArray(plumbing.defaultSkills)).toBe(true);
    expect(plumbing.defaultSkills.length).toBeGreaterThan(0);
    expect(plumbing.defaultSkills).toContain('Pipe Fitting & Installation');
  });
});
