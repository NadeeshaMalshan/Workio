import './workerTestUtils.js';
import React from 'react';
import { render, screen, waitFor } from '@testing-library/react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import axios from 'axios';
import WorkerDetail from '../../src/WorkerDetail.jsx';

vi.mock('axios');
vi.mock('react-leaflet', () => ({
  MapContainer: () => <div data-testid="map" />,
  TileLayer: () => <div />,
  Marker: () => <div />,
  useMapEvents: () => ({ flyTo: vi.fn(), invalidateSize: vi.fn() })
}));

vi.mock('../../src/components/M3TopNavbar.jsx', () => ({
  default: () => <nav data-testid="top-navbar" />
}));

describe('Frontend Worker TC-08: Worker Detail Error Handling', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    window.scrollTo = vi.fn();
  });

  it('displays error state when worker is not found or API rejects', async () => {
    delete window.location;
    window.location = new URL('http://localhost:5173/worker?id=999');

    axios.get.mockRejectedValueOnce(new Error('Worker not found'));

    render(<WorkerDetail />);

    await waitFor(() => {
      expect(screen.getByText(/Worker Profile Not Found/i)).toBeTruthy();
    });
  });
});
