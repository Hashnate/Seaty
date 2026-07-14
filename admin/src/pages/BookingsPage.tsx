import React, { useState, useEffect } from 'react';
import { useAuth } from '../hooks/useAuth';
import { getBookings } from '../api/client';
import { Search } from 'lucide-react';

interface BookingRecord {
  id: string;
  passenger_id: string;
  selected_seats: string[];
  total_price: number;
  platform_fee: number;
  payment_status: string;
  booking_status: string;
  created_at: string;
  trip?: {
    vehicle?: { name: string };
    route?: { origin: string; destination: string };
  };
  passenger?: { full_name: string; phone_number: string };
}

export default function BookingsPage() {
  const { token } = useAuth();
  const [bookings, setBookings] = useState<BookingRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');

  useEffect(() => {
    if (!token) return;
    setLoading(true);
    getBookings(token)
      .then(data => setBookings((data as BookingRecord[]) || []))
      .catch(() => setBookings([]))
      .finally(() => setLoading(false));
  }, [token]);

  const filtered = bookings.filter(b =>
    (b.passenger?.full_name || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
    (b.trip?.route?.origin || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
    (b.trip?.route?.destination || '').toLowerCase().includes(searchTerm.toLowerCase())
  );

  return (
    <div>
      <div className="page-header">
        <div>
          <h1 className="page-title">Bookings Log Directory</h1>
          <p className="page-subtitle">Track, filter, and inspect luxury seat bookings, pricing, and ticket collections.</p>
        </div>
      </div>

      <div className="table-card">
        <div style={{ display: 'flex', gap: '12px', marginBottom: '20px' }}>
          <div style={{ position: 'relative', flexGrow: 1 }}>
            <Search size={18} style={{ position: 'absolute', left: '12px', top: '13px', color: '#9ca3af' }} />
            <input
              type="text"
              placeholder="Search by Passenger Name or Route..."
              className="form-input"
              style={{ paddingLeft: '40px' }}
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
            />
          </div>
        </div>

        {loading ? (
          <div style={{ textAlign: 'center', padding: '40px', color: '#9ca3af' }}>Loading bookings...</div>
        ) : (
          <table className="custom-table">
            <thead>
              <tr>
                <th>Passenger</th>
                <th>Ticket Code</th>
                <th>Bus / Route</th>
                <th>Seats</th>
                <th>Fare</th>
                <th>Platform Fee</th>
                <th>Payment</th>
                <th>Booking</th>
                <th>Date</th>
              </tr>
            </thead>
            <tbody>
              {filtered.length === 0 ? (
                <tr>
                  <td colSpan={9} style={{ textAlign: 'center', padding: '30px', color: '#9ca3af' }}>
                    No bookings found.
                  </td>
                </tr>
              ) : (
                filtered.map(b => (
                  <tr key={b.id}>
                    <td>
                      <div><strong>{b.passenger?.full_name || 'Unknown'}</strong></div>
                      <div style={{ fontSize: '12px', color: '#9ca3af', marginTop: '2px' }}>{b.passenger?.phone_number}</div>
                    </td>
                    <td>
                      <span style={{ fontFamily: 'monospace', color: '#e65100', fontWeight: 'bold', fontSize: '12px' }}>
                        TKT-{b.id.substring(0, 8).toUpperCase()}
                      </span>
                    </td>
                    <td>
                      <div>{b.trip?.vehicle?.name || '—'}</div>
                      <div style={{ fontSize: '11px', color: '#9ca3af', marginTop: '2px' }}>
                        {b.trip?.route ? `${b.trip.route.origin} → ${b.trip.route.destination}` : '—'}
                      </div>
                    </td>
                    <td>{b.selected_seats.join(', ')}</td>
                    <td>Rs. {b.total_price.toLocaleString()}</td>
                    <td>Rs. {b.platform_fee.toLocaleString()}</td>
                    <td>
                      <span className={`badge ${b.payment_status === 'paid' ? 'badge-success' : b.payment_status === 'failed' ? 'badge-danger' : 'badge-warning'}`}>
                        {b.payment_status}
                      </span>
                    </td>
                    <td>
                      <span className={`badge ${b.booking_status === 'confirmed' ? 'badge-success' : b.booking_status === 'cancelled' ? 'badge-danger' : 'badge-warning'}`}>
                        {b.booking_status}
                      </span>
                    </td>
                    <td style={{ fontSize: '12px', whiteSpace: 'nowrap' }}>
                      {new Date(b.created_at).toLocaleDateString('en-LK')}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
