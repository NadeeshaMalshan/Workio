import './workerTestUtils.js';
import React from 'react';
import { render, screen } from '@testing-library/react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import WorkerRegister from '../../src/pages/worker/WorkerRegister.jsx';

describe('Frontend Worker TC-10: Worker Register Component', () => {
  beforeEach(() => {
    localStorage.clear();
  });

  it('renders Join as a Worker page with guidance for non-authenticated users', () => {
    render(<WorkerRegister />);

    expect(screen.getByText('Join as a Worker')).toBeTruthy();
    expect(screen.getByText(/Every user needs to be registered as a resident in order to upgrade to a worker profile/i)).toBeTruthy();
  });
});
