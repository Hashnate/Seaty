import { useState, useEffect } from 'react';
import { useAuth } from '../hooks/useAuth';
import { getDashboardStats, getBookings } from '../api/client';
import { DollarSign, Bus, Users, Clock, TrendingUp, CheckCircle } from 'lucide-react';

interface DashboardStats {
  total_companies: number;
  active_companies: number;
  total_vehicles: number;
  verified_vehicles: number;
  pending_approvals: number;
  total_bookings: number;
  confirmed_bookings: number;
  total_revenue: number;
  platform_fees_earned: number;
  total_passengers: number;
  total_owners: number;
  active_trips: number;
}

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

export default function OverviewPage() {
  const { token, user } = useAuth();
  const userRole = (user as { role?: string })?.role || 'admin';
  const [stats, setStats] = useState<DashboardStats | null>(null);
  const [bookings, setBookings] = useState<BookingRecord[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!token) return;
    setLoading(true);
    Promise.all([
      getDashboardStats(token).catch(() => null),
      getBookings(token).catch(() => []),
    ]).then(([statsData, bookingsData]) => {
      setStats(statsData as DashboardStats);
      setBookings((bookingsData as BookingRecord[]) || []);
    }).finally(() => setLoading(false));
  }, [token]);

  // Fallback stats when API not available
  const s = stats || {
    total_companies: 0,
    active_companies: 0,
    total_vehicles: 0,
    verified_vehicles: 0,
    pending_approvals: 0,
    total_bookings: 0,
    confirmed_bookings: 0,
    total_revenue: 0,
    platform_fees_earned: 0,
    total_passengers: 0,
    total_owners: 0,
    active_trips: 0,
  };

  return (
    <div>
      <div className="page-header">
        <div>
          <h1 className="page-title">{userRole === 'owner' ? 'Company Operational Dashboard' : 'Operational Dashboard'}</h1>
          <p className="page-subtitle">
            {userRole === 'owner' 
              ? 'Real-time stats of your company fleet, bookings, and ticket revenue.' 
              : 'Real-time stats of luxury buses, companies, and booking revenue.'}
          </p>
        </div>
        <div className="badge" style={{ background: 'rgba(16, 185, 129, 0.08)', border: '1px solid rgba(16, 185, 129, 0.15)', color: '#10b981' }}>
          <span className="live-status-dot" />
          {loading ? 'Loading...' : 'Live Data'}
        </div>
      </div>

      <div className="stats-grid">
        <div className="stat-card">
          <div className="stat-header">
            <span>{userRole === 'owner' ? 'Gross Ticket Revenue' : 'Gross Ticket Revenue'}</span>
            <DollarSign size={18} style={{ color: '#2563eb' }} />
          </div>
          <div className="stat-value">Rs. {s.total_revenue.toLocaleString()}</div>
          <div className="stat-trend up">
            <TrendingUp size={14} /> {userRole === 'owner' ? 'Platform Fees Paid: Rs. ' : 'Platform Fees: Rs. '}{s.platform_fees_earned.toLocaleString()}
          </div>
        </div>
        <div className="stat-card">
          <div className="stat-header">
            <span>{userRole === 'owner' ? 'Company Fleet' : 'Bus Companies'}</span>
            <Bus size={18} style={{ color: '#2563eb' }} />
          </div>
          <div className="stat-value">{userRole === 'owner' ? s.total_vehicles : s.total_companies}</div>
          <div className="stat-trend up">
            <TrendingUp size={14} /> 
            {userRole === 'owner' 
              ? `${s.verified_vehicles} verified • ${s.pending_approvals} pending` 
              : `${s.active_companies} active • ${s.total_vehicles} vehicles`}
          </div>
        </div>
        <div className="stat-card">
          <div className="stat-header">
            <span>Active Bookings</span>
            <Users size={18} style={{ color: '#10b981' }} />
          </div>
          <div className="stat-value">{s.total_bookings}</div>
          <div className="stat-trend up">
            <TrendingUp size={14} /> {s.confirmed_bookings} confirmed
          </div>
        </div>
        <div className="stat-card">
          <div className="stat-header">
            <span>{userRole === 'owner' ? 'Pending Approvals' : 'Pending Approvals'}</span>
            <Clock size={18} style={{ color: '#f59e0b' }} />
          </div>
          <div className="stat-value">{s.pending_approvals}</div>
          <div className="stat-trend">
            {userRole === 'owner' ? 'Your vehicles pending verification' : 'Vehicles pending verification'}
          </div>
        </div>
      </div>

      {/* Quick Summary Layout */}
      <div style={{ display: 'grid', gridTemplateColumns: '2fr 1fr', gap: '30px' }}>
        <div className="table-card">
          <div className="table-header">
            <h3 className="table-title">Recent Bookings</h3>
            <Users size={18} style={{ color: '#9ca3af' }} />
          </div>
          <table className="custom-table">
            <thead>
              <tr>
                <th>Passenger</th>
                <th>Bus / Route</th>
                <th>Seats</th>
                <th>Total Fare</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              {bookings.length === 0 ? (
                <tr>
                  <td colSpan={5} style={{ textAlign: 'center', padding: '30px', color: '#9ca3af' }}>
                    {loading ? 'Loading...' : 'No bookings yet. Start the backend to see live data.'}
                  </td>
                </tr>
              ) : (
                bookings.slice(0, 5).map(b => (
                  <tr key={b.id}>
                    <td>
                      <div><strong>{b.passenger?.full_name || 'Unknown'}</strong></div>
                      <div style={{ fontSize: '11px', color: '#9ca3af', marginTop: '2px' }}>{b.passenger?.phone_number}</div>
                    </td>
                    <td>
                      <div>{b.trip?.vehicle?.name || '—'}</div>
                      <div style={{ fontSize: '11px', color: '#9ca3af' }}>
                        {b.trip?.route ? `${b.trip.route.origin} → ${b.trip.route.destination}` : '—'}
                      </div>
                    </td>
                    <td>{b.selected_seats.join(', ')}</td>
                    <td>Rs. {b.total_price.toLocaleString()}</td>
                    <td>
                      <span className={`badge ${b.payment_status === 'paid' ? 'badge-success' : b.payment_status === 'failed' ? 'badge-danger' : 'badge-warning'}`}>
                        {b.payment_status}
                      </span>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>

        <div className="table-card" style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
          <h3 className="table-title">{userRole === 'owner' ? 'Company Metrics' : 'Platform Metrics'}</h3>
          <div style={{ display: 'flex', gap: '12px', background: 'rgba(37, 99, 235, 0.06)', padding: '12px', borderRadius: '10px', border: '1px solid rgba(37, 99, 235, 0.15)' }}>
            <DollarSign size={18} style={{ color: '#2563eb', flexShrink: 0, marginTop: '2px' }} />
            <div style={{ fontSize: '13px' }}>
              <strong>{userRole === 'owner' ? 'Gross Revenue' : 'Platform Revenue'}</strong>
              <div style={{ color: '#9ca3af', marginTop: '4px' }}>
                {userRole === 'owner' 
                  ? `Commission paid: Rs. ${s.platform_fees_earned.toLocaleString()}` 
                  : `Commission earned: Rs. ${s.platform_fees_earned.toLocaleString()}`}
              </div>
            </div>
          </div>
          <div style={{ display: 'flex', gap: '12px', background: 'rgba(16, 185, 129, 0.08)', padding: '12px', borderRadius: '10px', border: '1px solid rgba(16, 185, 129, 0.2)' }}>
            <Users size={18} style={{ color: '#10b981', flexShrink: 0, marginTop: '2px' }} />
            <div style={{ fontSize: '13px' }}>
              <strong>{userRole === 'owner' ? 'Passengers Handled' : 'User Base'}</strong>
              <div style={{ color: '#9ca3af', marginTop: '4px' }}>
                {userRole === 'owner' 
                  ? `${s.total_passengers} distinct passengers` 
                  : `${s.total_passengers} passengers • ${s.total_owners} owners`}
              </div>
            </div>
          </div>
          <div style={{ display: 'flex', gap: '12px', background: 'rgba(245, 158, 11, 0.08)', padding: '12px', borderRadius: '10px', border: '1px solid rgba(245, 158, 11, 0.2)' }}>
            <Clock size={18} style={{ color: '#f59e0b', flexShrink: 0, marginTop: '2px' }} />
            <div style={{ fontSize: '13px' }}>
              <strong>{s.pending_approvals} Buses Pending</strong>
              <div style={{ color: '#9ca3af', marginTop: '4px' }}>
                {userRole === 'owner' 
                  ? 'Buses awaiting verification by admin' 
                  : 'Review documentation & permits'}
              </div>
            </div>
          </div>
          {s.active_trips > 0 && (
            <div style={{ display: 'flex', gap: '12px', background: 'rgba(16, 185, 129, 0.08)', padding: '12px', borderRadius: '10px', border: '1px solid rgba(16, 185, 129, 0.2)' }}>
              <CheckCircle size={18} style={{ color: '#10b981', flexShrink: 0, marginTop: '2px' }} />
              <div style={{ fontSize: '13px' }}>
                <strong>{s.active_trips} Active Trips</strong>
                <div style={{ color: '#9ca3af', marginTop: '4px' }}>Buses currently on route</div>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
