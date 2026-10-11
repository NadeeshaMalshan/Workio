import React from 'react';
import { render, screen } from '@testing-library/react';
import { describe, it, expect } from 'vitest';
import WorkerListCard from '../../src/components/agent/WorkerListCard.jsx';

describe('Frontend Worker TC-04: Worker List Card Empty State', () => {
  it('renders No Workers Found message when worker list is empty', () => {
    render(<WorkerListCard data={{ category: 'Solar Inverter', workers: [] }} />);

    expect(screen.getByText('No Workers Found')).toBeTruthy();
    expect(screen.getByText(/No verified professionals found matching Solar Inverter/i)).toBeTruthy();
  });
});
