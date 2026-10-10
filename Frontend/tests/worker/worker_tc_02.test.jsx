import React from 'react';
import { render, screen } from '@testing-library/react';
import { describe, it, expect } from 'vitest';
import WorkerContactCard from '../../src/components/WorkerContactCard.jsx';

describe('Frontend Worker TC-02: Worker Contact Card Rendering', () => {
  it('renders worker name, location, and verified status badge', () => {
    render(
      <WorkerContactCard
        workerName="Saman Kumara"
        location="Colombo 05"
        phoneNumber="077 123 4567"
        isVerified={true}
      />
    );

    expect(screen.getByText('Saman Kumara')).toBeTruthy();
    expect(screen.getByText('Colombo 05')).toBeTruthy();
    expect(screen.getByText('077 123 4567')).toBeTruthy();
    expect(screen.getByTitle('Verified')).toBeTruthy();
  });
});
