import React, { useState, useEffect } from 'react';
import { useAuth } from '../hooks/useAuth';
import CustomSelect from '../components/CustomSelect';
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
  passenger_details?: {
    primary?: {
      name: string;
      nic: string;
      gender: string;
      phone: string;
      booking_type: string;
    };
    guests?: Array<{
      seat: string;
      gender: string;
    }>;
  };
}

export default function BookingsPage() {
  const { token } = useAuth();
  const [bookings, setBookings] = useState<BookingRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');
  const [statusFilter, setStatusFilter] = useState<'all' | 'pending' | 'confirmed' | 'cancelled'>('all');
  const [expandedBookingId, setExpandedBookingId] = useState<string | null>(null);

  useEffect(() => {
    if (!token) return;
    setLoading(true);
    getBookings(token)
      .then(data => setBookings((data as BookingRecord[]) || []))
      .catch(() => setBookings([]))
      .finally(() => setLoading(false));
  }, [token]);

  const filtered = bookings.filter(b => {
    const matchesSearch = 
      (b.passenger?.full_name || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
      (b.trip?.route?.origin || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
      (b.trip?.route?.destination || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
      (b.passenger_details?.primary?.nic || '').toLowerCase().includes(searchTerm.toLowerCase());

    const matchesStatus = 
      statusFilter === 'all' || 
      b.booking_status === statusFilter;

    return matchesSearch && matchesStatus;
  });

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
              placeholder="Search by Passenger Name, Route or NIC..."
              className="form-input"
              style={{ paddingLeft: '40px' }}
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
            />
          </div>
          <CustomSelect
            options={[
              { value: 'all', label: 'All Booking Statuses' },
              { value: 'pending', label: 'Pending' },
              { value: 'confirmed', label: 'Confirmed' },
              { value: 'cancelled', label: 'Cancelled' }
            ]}
            value={statusFilter}
            onChange={(val) => setStatusFilter(val as any)}
            style={{ width: '220px' }}
          />
        </div>

        {loading ? (
          <div style={{ textAlign: 'center', padding: '40px', color: '#9ca3af' }}>Loading bookings...</div>
        ) : (
          <table className="custom-table">
            <thead>
              <tr>
                <th>Passenger / NIC</th>
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
                filtered.map(b => {
                  const isExpanded = expandedBookingId === b.id;
                  return (
                    <React.Fragment key={b.id}>
                      <tr 
                        onClick={() => setExpandedBookingId(isExpanded ? null : b.id)}
                        style={{ cursor: 'pointer', transition: 'background-color 0.2s' }}
                        className={isExpanded ? 'expanded-row-active' : ''}
                      >
                        <td>
                          <div>
                            <strong>{b.passenger_details?.primary?.name || b.passenger?.full_name || 'Unknown'}</strong>
                            {b.passenger_details?.primary?.booking_type === 'other' && (
                              <span style={{ fontSize: '10px', marginLeft: '6px', backgroundColor: 'rgba(37,99,235,0.15)', color: '#2563eb', padding: '2px 6px', borderRadius: '4px' }}>For Others</span>
                            )}
                          </div>
                          <div style={{ fontSize: '12px', color: '#9ca3af', marginTop: '2px' }}>
                            {b.passenger_details?.primary?.phone || b.passenger?.phone_number}
                          </div>
                          {b.passenger_details?.primary?.nic && (
                            <div style={{ fontSize: '11px', color: '#2563eb', marginTop: '2px', fontWeight: '500' }}>
                              NIC: {b.passenger_details.primary.nic}
                            </div>
                          )}
                        </td>
                        <td>
                          <span style={{ fontFamily: 'monospace', color: '#2563eb', fontWeight: 'bold', fontSize: '12px' }}>
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
                      {isExpanded && (
                        <tr>
                          <td colSpan={9} style={{ backgroundColor: 'rgba(255, 255, 255, 0.02)', padding: '16px 24px', borderBottom: '1px solid rgba(255, 255, 255, 0.05)' }}>
                            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '24px' }}>
                              <div>
                                <h4 style={{ margin: '0 0 12px 0', color: '#2563eb', fontSize: '12px', fontWeight: 'bold', textTransform: 'uppercase', letterSpacing: '0.5px' }}>Primary Passenger Info</h4>
                                {b.passenger_details?.primary ? (
                                  <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', fontSize: '13px' }}>
                                    <div><span style={{ color: '#9ca3af' }}>Name:</span> <strong>{b.passenger_details.primary.name}</strong></div>
                                    <div><span style={{ color: '#9ca3af' }}>NIC Number:</span> <strong>{b.passenger_details.primary.nic}</strong></div>
                                    <div><span style={{ color: '#9ca3af' }}>Gender:</span> <strong>{b.passenger_details.primary.gender}</strong></div>
                                    <div><span style={{ color: '#9ca3af' }}>Contact Phone:</span> <strong>{b.passenger_details.primary.phone}</strong></div>
                                    <div><span style={{ color: '#9ca3af' }}>Type:</span> <strong>{b.passenger_details.primary.booking_type === 'self' ? 'Self Booking' : 'Booked for Someone Else'}</strong></div>
                                  </div>
                                ) : (
                                  <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', fontSize: '13px' }}>
                                    <div><span style={{ color: '#9ca3af' }}>Account Holder:</span> <strong>{b.passenger?.full_name || 'Guest User'}</strong></div>
                                    <div><span style={{ color: '#9ca3af' }}>Phone:</span> <strong>{b.passenger?.phone_number || '—'}</strong></div>
                                    <div style={{ fontStyle: 'italic', marginTop: '4px', color: '#f59e0b', fontSize: '12px' }}>Legacy booking (Detailed passenger profile was not captured during checkout).</div>
                                  </div>
                                )}
                              </div>
                              <div>
                                <h4 style={{ margin: '0 0 12px 0', color: '#2563eb', fontSize: '12px', fontWeight: 'bold', textTransform: 'uppercase', letterSpacing: '0.5px' }}>Additional Seat Genders</h4>
                                {b.passenger_details?.guests && b.passenger_details.guests.length > 0 ? (
                                  <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', fontSize: '13px' }}>
                                    {b.passenger_details.guests.map((g, idx) => (
                                      <div key={idx}><span style={{ color: '#9ca3af' }}>Seat {g.seat}:</span> <strong>{g.gender}</strong></div>
                                    ))}
                                  </div>
                                ) : (
                                  <div style={{ fontSize: '13px', color: '#9ca3af', fontStyle: 'italic' }}>
                                    No guest seats (Single seat booking, or legacy transaction).
                                  </div>
                                )}
                              </div>
                            </div>
                          </td>
                        </tr>
                      )}
                    </React.Fragment>
                  );
                })
              )}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
