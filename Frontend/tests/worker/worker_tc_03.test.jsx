import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import { describe, it, expect, vi } from 'vitest';
import WorkerContactCard from '../../src/components/WorkerContactCard.jsx';

describe('Frontend Worker TC-03: Worker Contact Card Copy & Call Action', () => {
  it('triggers onCallNow and copies formatted number', async () => {
    const handleCallNow = vi.fn();
    const handleCopy = vi.fn();

    // Mock navigator.clipboard
    Object.assign(navigator, {
      clipboard: {
        writeText: vi.fn().mockImplementation(() => Promise.resolve()),
      },
    });

    render(
      <WorkerContactCard
        workerName="Saman Kumara"
        location="Colombo"
        phoneNumber="077 123 4567"
        onCallNow={handleCallNow}
        onCopy={handleCopy}
      />
    );

    const callBtn = screen.getByText(/Call Now/i);
    fireEvent.click(callBtn);
    expect(handleCallNow).toHaveBeenCalledWith('0771234567');

    const copyBtn = screen.getByText(/Copy/i);
    fireEvent.click(copyBtn);
    expect(navigator.clipboard.writeText).toHaveBeenCalledWith('0771234567');
    expect(handleCopy).toHaveBeenCalledWith('0771234567');
  });
});
