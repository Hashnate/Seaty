import React, { useState, useEffect } from 'react';
import { useAuth } from '../hooks/useAuth';
import CustomSelect from '../components/CustomSelect';
import CustomDatePicker from '../components/CustomDatePicker';
import { 
  getTrips, 
  getVehicles, 
  getRoutes, 
  deleteTrip, 
  getSchedules,
  createSchedule,
  updateSchedule,
  deleteSchedule,
  toggleSchedule,
  getScheduleOverrides,
  createScheduleOverride,
  deleteScheduleOverride
} from '../api/client';
import { 
  Plus, 
  Trash2, 
  Calendar, 
  MapPin, 
  Settings, 
  Clock, 
  AlertCircle
} from 'lucide-react';

interface TripRecord {
  id: string;
  vehicle_id: string;
  route_id: string;
  departure_time: string;
  arrival_time: string;
  price_per_seat: number;
  status: string;
  vehicle?: { name: string; registration_number: string };
  route?: { origin: string; destination: string };
}

interface ScheduleRecord {
  id: string;
  vehicle_id: string;
  route_id: string;
  departure_time: string; // "HH:MM:SS"
  arrival_time: string; // "HH:MM:SS"
  price_per_seat: number;
  schedule_type: string; // 'daily', 'weekdays', 'weekends', 'custom'
  custom_days: number[]; // 0=Mon, 6=Sun
  effective_from: string; // YYYY-MM-DD
  effective_until: string | null;
  is_active: boolean;
  vehicle?: { name: string; registration_number: string };
  route?: { origin: string; destination: string };
}

interface OverrideRecord {
  id: string;
  schedule_id: string;
  override_date: string;
  replacement_vehicle_id: string;
  reason: string | null;
  replacement_vehicle?: { name: string; registration_number: string };
}

interface VehicleRecord {
  id: string;
  name: string;
  registration_number: string;
  is_verified: boolean;
}

interface RouteRecord {
  id: string;
  origin: string;
  destination: string;
}

const DAYS_OF_WEEK = [
  { value: 0, label: 'Mon' },
  { value: 1, label: 'Tue' },
  { value: 2, label: 'Wed' },
  { value: 3, label: 'Thu' },
  { value: 4, label: 'Fri' },
  { value: 5, label: 'Sat' },
  { value: 6, label: 'Sun' }
];

const calculateArrivalTime = (depTimeStr: string, hoursStr: string, minutesStr: string) => {
  if (!depTimeStr) return { time: '', isNextDay: false, display: '—' };
  
  const [h, m] = depTimeStr.split(':').map(Number);
  const durH = parseInt(hoursStr, 10) || 0;
  const durM = parseInt(minutesStr, 10) || 0;
  
  const depTotalMinutes = h * 60 + m;
  const durTotalMinutes = durH * 60 + durM;
  
  const arrTotalMinutes = depTotalMinutes + durTotalMinutes;
  
  const arrHour = Math.floor(arrTotalMinutes / 60) % 24;
  const arrMinute = arrTotalMinutes % 60;
  
  const isNextDay = arrTotalMinutes >= 24 * 60;
  
  const formattedHour = String(arrHour).padStart(2, '0');
  const formattedMinute = String(arrMinute).padStart(2, '0');
  const arrivalTimeVal = `${formattedHour}:${formattedMinute}`;
  
  const ampm = arrHour >= 12 ? 'PM' : 'AM';
  const displayHour = arrHour % 12 || 12;
  const displayMinute = String(arrMinute).padStart(2, '0');
  const displayStr = `${String(displayHour).padStart(2, '0')}:${displayMinute} ${ampm}${isNextDay ? ' (Next Day)' : ''}`;
  
  return {
    time: arrivalTimeVal,
    isNextDay,
    display: displayStr
  };
};

export default function MyTripsPage() {
  const { token } = useAuth();
  
  // Tab State
  const [activeTab, setActiveTab] = useState<'schedules' | 'trips'>('schedules');
  
  // Lists
  const [trips, setTrips] = useState<TripRecord[]>([]);
  const [schedules, setSchedules] = useState<ScheduleRecord[]>([]);
  const [vehicles, setVehicles] = useState<VehicleRecord[]>([]);
  const [routes, setRoutes] = useState<RouteRecord[]>([]);
  
  // Loading & Modals
  const [loading, setLoading] = useState(true);
  const [showScheduleModal, setShowScheduleModal] = useState(false);
  const [showOverrideModal, setShowOverrideModal] = useState(false);
  const [activeActionMenuId, setActiveActionMenuId] = useState<string | null>(null);
  
  // Selected schedule for overrides
  const [selectedSchedule, setSelectedSchedule] = useState<ScheduleRecord | null>(null);
  const [overrides, setOverrides] = useState<OverrideRecord[]>([]);
  const [loadingOverrides, setLoadingOverrides] = useState(false);
  
  // Date Filters
  const [tripDateFilter, setTripDateFilter] = useState(new Date().toISOString().split('T')[0]);
  
  // Schedule Form State
  const [editingScheduleId, setEditingScheduleId] = useState<string | null>(null);
  const [selectedVehicle, setSelectedVehicle] = useState('');
  const [selectedRoute, setSelectedRoute] = useState('');
  const [departureTime, setDepartureTime] = useState('23:00');
  const [durationHours, setDurationHours] = useState('6');
  const [durationMinutes, setDurationMinutes] = useState('0');
  const [price, setPrice] = useState('1600');
  const [scheduleType, setScheduleType] = useState('daily');
  const [customDays, setCustomDays] = useState<number[]>([]);
  const [effectiveFrom, setEffectiveFrom] = useState(new Date().toISOString().split('T')[0]);
  const [effectiveUntil, setEffectiveUntil] = useState('');
  
  // Override Form State
  const [overrideDate, setOverrideDate] = useState(() => {
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    return tomorrow.toISOString().split('T')[0];
  });
  const [overrideVehicleId, setOverrideVehicleId] = useState('');
  const [overrideReason, setOverrideReason] = useState('');
  
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');
  const [overrideError, setOverrideError] = useState('');

  // Fetching Data
  const fetchSchedules = () => {
    if (!token) return;
    setLoading(true);
    getSchedules(token)
      .then(data => setSchedules((data as ScheduleRecord[]) || []))
      .catch(() => setSchedules([]))
      .finally(() => setLoading(false));
  };

  const fetchTripsForDate = () => {
    if (!token) return;
    setLoading(true);
    getTrips(token, tripDateFilter)
      .then(data => setTrips((data as TripRecord[]) || []))
      .catch(() => setTrips([]))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    if (!token) return;
    
    // Fetch static templates once
    getVehicles(token)
      .then(data => setVehicles(((data as VehicleRecord[]) || []).filter(v => v.is_verified)))
      .catch(() => setVehicles([]));
      
    getRoutes(token)
      .then(data => setRoutes((data as RouteRecord[]) || []))
      .catch(() => setRoutes([]));
  }, [token]);

  useEffect(() => {
    if (activeTab === 'schedules') {
      fetchSchedules();
    } else {
      fetchTripsForDate();
    }
  }, [token, activeTab, tripDateFilter]);

  // Handle schedule active/pause toggle
  const handleToggleSchedule = async (id: string) => {
    if (!token) return;
    try {
      await toggleSchedule(token, id);
      fetchSchedules();
    } catch (err: any) {
      alert(err.message || 'Failed to toggle schedule state');
    }
  };

  const handleEditScheduleClick = (s: ScheduleRecord) => {
    setEditingScheduleId(s.id);
    setSelectedVehicle(s.vehicle_id);
    setSelectedRoute(s.route_id);
    
    // Time formats from backend "HH:MM:SS" -> convert to "HH:MM"
    const depTimeFormatted = s.departure_time.substring(0, 5);
    const arrTimeFormatted = s.arrival_time.substring(0, 5);
    setDepartureTime(depTimeFormatted);

    // Calculate duration from departure and arrival times
    const [depH, depM] = depTimeFormatted.split(':').map(Number);
    const [arrH, arrM] = arrTimeFormatted.split(':').map(Number);
    const depMin = depH * 60 + depM;
    let arrMin = arrH * 60 + arrM;
    if (arrMin < depMin) {
      arrMin += 24 * 60; // Next day arrival
    }
    const diffMin = arrMin - depMin;
    setDurationHours(String(Math.floor(diffMin / 60)));
    setDurationMinutes(String(diffMin % 60));
    
    setPrice(String(s.price_per_seat));
    setScheduleType(s.schedule_type);
    setCustomDays(s.custom_days || []);
    setEffectiveFrom(s.effective_from);
    setEffectiveUntil(s.effective_until || '');
    
    setError('');
    setShowScheduleModal(true);
  };

  const handleDeleteSchedule = async (id: string) => {
    if (!token || !window.confirm('Are you sure you want to delete this schedule? This will delete all generated trips under this schedule.')) return;
    try {
      await deleteSchedule(token, id);
      fetchSchedules();
    } catch (err: any) {
      alert(err.message || 'Failed to delete schedule');
    }
  };

  const handleSaveSchedule = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!token) return;
    setError('');
    
    if (!selectedVehicle) return setError('Please select a verified bus');
    if (!selectedRoute) return setError('Please select a route template');
    if (!departureTime) return setError('Please enter a departure time');
    if (scheduleType === 'custom' && customDays.length === 0) return setError('Please select at least one day for custom schedule');
    
    setSubmitting(true);
    try {
      const computedArrival = calculateArrivalTime(departureTime, durationHours, durationMinutes).time;
      const scheduleData = {
        vehicle_id: selectedVehicle,
        route_id: selectedRoute,
        departure_time: departureTime,
        arrival_time: computedArrival,
        price_per_seat: Number(price),
        schedule_type: scheduleType,
        custom_days: scheduleType === 'custom' ? customDays : [],
        effective_from: effectiveFrom,
        effective_until: effectiveUntil || null
      };

      if (editingScheduleId) {
        await updateSchedule(token, editingScheduleId, scheduleData);
      } else {
        await createSchedule(token, scheduleData);
      }
      
      setShowScheduleModal(false);
      fetchSchedules();
    } catch (err: any) {
      setError(err.message || 'Failed to save recurring schedule');
    } finally {
      setSubmitting(false);
    }
  };

  // Bus Overrides
  const openOverridesModal = async (s: ScheduleRecord) => {
    if (!token) return;
    setSelectedSchedule(s);
    setOverrides([]);
    setLoadingOverrides(true);
    setOverrideError('');
    setOverrideReason('');
    
    // Pre-populate override vehicle with first option that is not the default
    const availableOthers = vehicles.filter(v => v.id !== s.vehicle_id);
    if (availableOthers.length > 0) {
      setOverrideVehicleId(availableOthers[0].id);
    } else {
      setOverrideVehicleId('');
    }
    
    setShowOverrideModal(true);
    try {
      const data = await getScheduleOverrides(token, s.id);
      setOverrides((data as OverrideRecord[]) || []);
    } catch (err) {
      console.error(err);
    } finally {
      setLoadingOverrides(false);
    }
  };

  const handleAddOverride = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!token || !selectedSchedule) return;
    setOverrideError('');
    
    if (!overrideVehicleId) return setOverrideError('Please select a replacement bus');
    if (!overrideDate) return setOverrideError('Please select a date for the override');
    
    setSubmitting(true);
    try {
      await createScheduleOverride(token, selectedSchedule.id, {
        override_date: overrideDate,
        replacement_vehicle_id: overrideVehicleId,
        reason: overrideReason || null
      });
      
      // Refresh list
      const data = await getScheduleOverrides(token, selectedSchedule.id);
      setOverrides((data as OverrideRecord[]) || []);
      
      setOverrideReason('');
    } catch (err: any) {
      setOverrideError(err.message || 'Failed to apply bus override');
    } finally {
      setSubmitting(false);
    }
  };

  const handleDeleteOverride = async (overrideId: string) => {
    if (!token || !selectedSchedule) return;
    if (!window.confirm('Are you sure you want to remove this bus override? The trip will revert to using the default schedule bus.')) return;
    
    try {
      await deleteScheduleOverride(token, overrideId);
      const data = await getScheduleOverrides(token, selectedSchedule.id);
      setOverrides((data as OverrideRecord[]) || []);
    } catch (err: any) {
      alert(err.message || 'Failed to delete override');
    }
  };

  const handleCancelTrip = async (id: string) => {
    if (!token || !window.confirm('Are you sure you want to cancel this specific trip instance? All confirmed bookings will receive cancellation notifications.')) return;
    try {
      await deleteTrip(token, id);
      fetchTripsForDate();
    } catch (err: any) {
      alert(err.message || 'Failed to cancel trip instance');
    }
  };

  const toggleCustomDay = (day: number) => {
    if (customDays.includes(day)) {
      setCustomDays(customDays.filter(d => d !== day));
    } else {
      setCustomDays([...customDays, day].sort());
    }
  };

  return (
    <div>
      <div className="page-header" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div>
          <h1 className="page-title">Trip & Timing Scheduler</h1>
          <p className="page-subtitle">Schedule recurring bus routes, set daily patterns, and manage date-specific bus swaps.</p>
        </div>
        
        {activeTab === 'schedules' && (
          <button
            className="btn-primary"
            onClick={() => {
              setEditingScheduleId(null);
              setSelectedVehicle(vehicles[0]?.id || '');
              setSelectedRoute(routes[0]?.id || '');
              setDepartureTime('23:00');
              setDurationHours('6');
              setDurationMinutes('0');
              setPrice('1600');
              setScheduleType('daily');
              setCustomDays([]);
              setEffectiveFrom(new Date().toISOString().split('T')[0]);
              setEffectiveUntil('');
              setError('');
              setShowScheduleModal(true);
            }}
            style={{ display: 'flex', alignItems: 'center', gap: '8px', padding: '10px 18px', width: 'auto' }}
          >
            <Plus size={16} /> Create Recurring Schedule
          </button>
        )}
      </div>

      {/* Tabs Layout Selector */}
      <div style={{ display: 'flex', gap: '16px', borderBottom: '1px solid var(--border-color)', marginBottom: '24px', paddingBottom: '0' }}>
        <button
          onClick={() => setActiveTab('schedules')}
          style={{
            padding: '12px 18px',
            background: 'none',
            border: 'none',
            borderBottom: activeTab === 'schedules' ? '3px solid var(--color-primary)' : '3px solid transparent',
            color: activeTab === 'schedules' ? 'var(--color-primary)' : 'var(--text-muted)',
            fontWeight: '600',
            cursor: 'pointer',
            fontSize: '14px',
            transition: 'var(--transition-smooth)'
          }}
        >
          Recurring Schedules
        </button>
        <button
          onClick={() => setActiveTab('trips')}
          style={{
            padding: '12px 18px',
            background: 'none',
            border: 'none',
            borderBottom: activeTab === 'trips' ? '3px solid var(--color-primary)' : '3px solid transparent',
            color: activeTab === 'trips' ? 'var(--color-primary)' : 'var(--text-muted)',
            fontWeight: '600',
            cursor: 'pointer',
            fontSize: '14px',
            transition: 'var(--transition-smooth)'
          }}
        >
          Upcoming Trip Instances
        </button>
      </div>

      {/* TAB CONTENT 1: RECURRING SCHEDULES */}
      {activeTab === 'schedules' && (
        <div className="table-card">
          {loading ? (
            <div style={{ textAlign: 'center', padding: '40px', color: '#9ca3af' }}>Loading schedules...</div>
          ) : schedules.length === 0 ? (
            <div style={{ textAlign: 'center', padding: '60px', color: '#9ca3af' }}>
              <Clock size={48} style={{ marginBottom: '16px', color: 'rgba(0,0,0,0.1)' }} />
              <div>No recurring schedules established.</div>
              <button
                className="btn-primary"
                onClick={() => {
                  setEditingScheduleId(null);
                  setSelectedVehicle(vehicles[0]?.id || '');
                  setSelectedRoute(routes[0]?.id || '');
                  setDepartureTime('23:00');
                  setDurationHours('6');
                  setDurationMinutes('0');
                  setPrice('1600');
                  setScheduleType('daily');
                  setCustomDays([]);
                  setEffectiveFrom(new Date().toISOString().split('T')[0]);
                  setEffectiveUntil('');
                  setError('');
                  setShowScheduleModal(true);
                }}
                style={{ marginTop: '16px', width: 'auto' }}
              >
                Create Your First Schedule
              </button>
            </div>
          ) : (
            <table className="custom-table">
              <thead>
                <tr>
                  <th>Bus Info</th>
                  <th>Route Template</th>
                  <th>Timings</th>
                  <th>Frequency & Days</th>
                  <th>Validity Period</th>
                  <th>Status</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {schedules.map(s => {
                  let freqLabel = 'Daily';
                  if (s.schedule_type === 'weekdays') freqLabel = 'Weekdays (Mon-Fri)';
                  else if (s.schedule_type === 'weekends') freqLabel = 'Weekends (Sat-Sun)';
                  else if (s.schedule_type === 'custom') {
                    const days = s.custom_days.map(d => DAYS_OF_WEEK.find(day => day.value === d)?.label).join(', ');
                    freqLabel = `Custom (${days})`;
                  }

                  return (
                    <tr key={s.id}>
                      <td>
                        <div style={{ fontWeight: 'bold' }}>{s.vehicle?.name || '—'}</div>
                        <div style={{ fontSize: '11px', color: '#9ca3af', fontFamily: 'monospace', marginTop: '2px' }}>
                          {s.vehicle?.registration_number}
                        </div>
                      </td>
                      <td>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '4px', fontWeight: '500' }}>
                          <MapPin size={13} color="#e65100" />
                          {s.route ? `${s.route.origin} → ${s.route.destination}` : '—'}
                        </div>
                      </td>
                      <td>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '4px', fontSize: '13px' }}>
                          <Clock size={13} style={{ color: 'var(--text-muted)' }} />
                          <span>{s.departure_time.substring(0, 5)} - {s.arrival_time.substring(0, 5)}</span>
                        </div>
                      </td>
                      <td>
                        <span style={{ fontSize: '12px', fontWeight: 600, color: 'var(--color-secondary)' }}>
                          {freqLabel}
                        </span>
                      </td>
                      <td>
                        <div style={{ fontSize: '12.5px' }}>
                          <span>{s.effective_from}</span>
                          {s.effective_until ? <span style={{ color: 'var(--text-muted)' }}> to {s.effective_until}</span> : <span style={{ color: 'var(--text-muted)' }}> (Indefinite)</span>}
                        </div>
                      </td>
                      <td>
                        <button
                          onClick={() => handleToggleSchedule(s.id)}
                          style={{
                            background: 'none',
                            border: 'none',
                            cursor: 'pointer',
                            padding: '4px',
                            display: 'inline-flex',
                            alignItems: 'center'
                          }}
                          title={s.is_active ? "Click to Pause" : "Click to Resume"}
                        >
                          <span className={`badge ${s.is_active ? 'badge-success' : 'badge-danger'}`}>
                            {s.is_active ? 'Active' : 'Paused'}
                          </span>
                        </button>
                      </td>
                      <td style={{ position: 'relative' }}>
                        <button
                          className="btn-action"
                          style={{
                            padding: '5px 10px',
                            fontSize: '12.5px',
                            borderRadius: '6px',
                            background: activeActionMenuId === s.id ? 'rgba(10,37,64,0.1)' : 'rgba(0,0,0,0.03)',
                            border: '1px solid rgba(0,0,0,0.08)',
                            color: 'var(--text-main)',
                            cursor: 'pointer',
                            display: 'inline-flex',
                            alignItems: 'center',
                            gap: '4px',
                          }}
                          onClick={() => setActiveActionMenuId(activeActionMenuId === s.id ? null : s.id)}
                        >
                          <Settings size={14} /> Actions
                        </button>
                        
                        {activeActionMenuId === s.id && (
                          <>
                            <div
                              style={{ position: 'fixed', top: 0, left: 0, right: 0, bottom: 0, zIndex: 998 }}
                              onClick={() => setActiveActionMenuId(null)}
                            />
                            
                            <div
                              style={{
                                position: 'absolute',
                                right: 0,
                                top: '100%',
                                marginTop: '4px',
                                background: 'white',
                                border: '1px solid rgba(0,0,0,0.08)',
                                borderRadius: '8px',
                                boxShadow: '0 4px 12px rgba(0,0,0,0.08)',
                                zIndex: 999,
                                minWidth: '150px',
                                overflow: 'hidden'
                              }}
                            >
                              <div
                                style={{
                                  padding: '8px 12px',
                                  cursor: 'pointer',
                                  fontSize: '13px',
                                  color: 'var(--text-main)',
                                  textAlign: 'left',
                                  transition: 'background 0.15s'
                                }}
                                onClick={() => {
                                  openOverridesModal(s);
                                  setActiveActionMenuId(null);
                                }}
                                onMouseEnter={(e) => e.currentTarget.style.background = '#f8fafc'}
                                onMouseLeave={(e) => e.currentTarget.style.background = 'transparent'}
                              >
                                Bus Overrides
                              </div>
                              <div
                                style={{
                                  padding: '8px 12px',
                                  cursor: 'pointer',
                                  fontSize: '13px',
                                  color: 'var(--text-main)',
                                  textAlign: 'left',
                                  transition: 'background 0.15s'
                                }}
                                onClick={() => {
                                  handleEditScheduleClick(s);
                                  setActiveActionMenuId(null);
                                }}
                                onMouseEnter={(e) => e.currentTarget.style.background = '#f8fafc'}
                                onMouseLeave={(e) => e.currentTarget.style.background = 'transparent'}
                              >
                                Edit Schedule
                              </div>
                              <div
                                style={{
                                  padding: '8px 12px',
                                  cursor: 'pointer',
                                  fontSize: '13px',
                                  color: '#ef4444',
                                  borderTop: '1px solid rgba(0,0,0,0.04)',
                                  textAlign: 'left',
                                  transition: 'background 0.15s'
                                }}
                                onClick={() => {
                                  handleDeleteSchedule(s.id);
                                  setActiveActionMenuId(null);
                                }}
                                onMouseEnter={(e) => e.currentTarget.style.background = '#fef2f2'}
                                onMouseLeave={(e) => e.currentTarget.style.background = 'transparent'}
                              >
                                Delete Schedule
                              </div>
                            </div>
                          </>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </div>
      )}

      {/* TAB CONTENT 2: TRIP INSTANCES FOR DATE */}
      {activeTab === 'trips' && (
        <div>
          <div style={{ 
            display: 'flex', 
            justifyContent: 'space-between', 
            alignItems: 'center', 
            background: 'var(--bg-secondary)', 
            padding: '12px 18px', 
            borderRadius: '10px', 
            marginBottom: '16px',
            border: '1px solid var(--border-color)'
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
              <span style={{ fontSize: '13.5px', fontWeight: 600 }}>Filter Departure Date:</span>
              <CustomDatePicker
                value={tripDateFilter}
                onChange={setTripDateFilter}
                style={{ width: '180px' }}
              />
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '12.5px', color: 'var(--text-muted)' }}>
              <AlertCircle size={15} style={{ color: 'var(--color-primary)' }} />
              <span>Passengers can search schedules up to 5 days in advance. Schedules generate automatically.</span>
            </div>
          </div>

          <div className="table-card">
            {loading ? (
              <div style={{ textAlign: 'center', padding: '40px', color: '#9ca3af' }}>Loading active instances...</div>
            ) : trips.length === 0 ? (
              <div style={{ textAlign: 'center', padding: '50px', color: '#9ca3af' }}>
                <Calendar size={48} style={{ marginBottom: '16px', color: 'rgba(0,0,0,0.1)' }} />
                <div>No trips are running or scheduled for this date.</div>
              </div>
            ) : (
              <table className="custom-table">
                <thead>
                  <tr>
                    <th>Bus Info</th>
                    <th>Route Name</th>
                    <th>Departure Datetime</th>
                    <th>Seat Fare</th>
                    <th>Status</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {trips.map(t => (
                    <tr key={t.id}>
                      <td>
                        <div style={{ fontWeight: 'bold' }}>{t.vehicle?.name || '—'}</div>
                        <div style={{ fontSize: '11px', color: '#9ca3af', fontFamily: 'monospace', marginTop: '2px' }}>
                          {t.vehicle?.registration_number}
                        </div>
                      </td>
                      <td>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '4px', fontWeight: '500' }}>
                          <MapPin size={13} color="#e65100" />
                          {t.route ? `${t.route.origin} → ${t.route.destination}` : '—'}
                        </div>
                      </td>
                      <td>
                        {new Date(t.departure_time).toLocaleString('en-LK', { dateStyle: 'medium', timeStyle: 'short' })}
                      </td>
                      <td>
                        <div style={{ fontWeight: 'bold', color: '#e65100' }}>Rs. {t.price_per_seat.toLocaleString()}</div>
                      </td>
                      <td>
                        <span className={`badge ${t.status === 'scheduled' ? 'badge-success' : 'badge-warning'}`}>
                          {t.status}
                        </span>
                      </td>
                      <td>
                        <button
                          onClick={() => handleCancelTrip(t.id)}
                          style={{
                            background: 'none',
                            border: 'none',
                            color: '#ef4444',
                            cursor: 'pointer',
                            display: 'inline-flex',
                            alignItems: 'center',
                            gap: '4px',
                            fontWeight: '600',
                            fontSize: '12.5px'
                          }}
                        >
                          <Trash2 size={13} /> Cancel Instance
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </div>
      )}

      {/* SCHEDULE MODAL (CREATE / EDIT) */}
      {showScheduleModal && (
        <div className="modal-backdrop" style={{ position: 'fixed', top: 0, left: 0, right: 0, bottom: 0, backgroundColor: 'rgba(0,0,0,0.5)', display: 'flex', justifyContent: 'center', alignItems: 'center', zIndex: 1000 }}>
          <div className="table-card" style={{ width: '480px', background: '#0f172a', border: '1px solid rgba(255,255,255,0.1)', padding: '24px', borderRadius: '16px' }}>
            <h3 style={{ margin: '0 0 16px 0', fontSize: '18px', color: 'white' }}>
              {editingScheduleId ? 'Edit Recurring Schedule' : 'Create Recurring Schedule'}
            </h3>
            {error && <div style={{ color: '#ef4444', marginBottom: '12px', fontSize: '13px' }}>{error}</div>}
            
            <form onSubmit={handleSaveSchedule}>
              <div className="form-group">
                <label className="form-label" style={{ color: '#9ca3af' }}>Select Default Bus</label>
                <CustomSelect
                  options={vehicles.map(v => ({ value: v.id, label: `${v.name} (${v.registration_number})` }))}
                  value={selectedVehicle}
                  onChange={setSelectedVehicle}
                  placeholder="-- Choose Bus --"
                />
              </div>
              
              <div className="form-group">
                <label className="form-label" style={{ color: '#9ca3af' }}>Select Route Template</label>
                <CustomSelect
                  options={routes.map(r => ({ value: r.id, label: `${r.origin} to ${r.destination}` }))}
                  value={selectedRoute}
                  onChange={setSelectedRoute}
                  placeholder="-- Choose Route --"
                />
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: '1.2fr 1fr', gap: '12px' }}>
                <div className="form-group">
                  <label className="form-label" style={{ color: '#9ca3af' }}>Departure Time</label>
                  <input type="time" className="form-input" style={{ backgroundColor: '#1e293b', color: 'white', border: '1px solid rgba(255,255,255,0.1)' }} value={departureTime} onChange={(e) => setDepartureTime(e.target.value)} required />
                </div>
                
                <div className="form-group">
                  <label className="form-label" style={{ color: '#9ca3af' }}>Journey Duration</label>
                  <div style={{ display: 'flex', gap: '4px', alignItems: 'center' }}>
                    <input 
                      type="number" 
                      className="form-input" 
                      style={{ backgroundColor: '#1e293b', color: 'white', border: '1px solid rgba(255,255,255,0.1)', padding: '12px 8px', textAlign: 'center' }} 
                      min="0" 
                      max="23" 
                      value={durationHours} 
                      onChange={(e) => setDurationHours(e.target.value)} 
                      placeholder="Hrs" 
                      required 
                    />
                    <span style={{ color: '#9ca3af', fontSize: '12px' }}>h</span>
                    <input 
                      type="number" 
                      className="form-input" 
                      style={{ backgroundColor: '#1e293b', color: 'white', border: '1px solid rgba(255,255,255,0.1)', padding: '12px 8px', textAlign: 'center' }} 
                      min="0" 
                      max="59" 
                      value={durationMinutes} 
                      onChange={(e) => setDurationMinutes(e.target.value)} 
                      placeholder="Mins" 
                      required 
                    />
                    <span style={{ color: '#9ca3af', fontSize: '12px' }}>m</span>
                  </div>
                </div>
              </div>

              {/* Calculated Arrival Time Display */}
              <div className="form-group" style={{ 
                backgroundColor: 'rgba(255,255,255,0.02)', 
                border: '1px dashed rgba(255,255,255,0.1)', 
                borderRadius: '10px', 
                padding: '12px',
                marginTop: '-8px',
                marginBottom: '16px'
              }}>
                <div style={{ fontSize: '11px', color: '#9ca3af', textTransform: 'uppercase', fontWeight: 600 }}>Estimated Arrival Time</div>
                <div style={{ fontSize: '15px', color: 'white', fontWeight: 700, marginTop: '4px', display: 'flex', alignItems: 'center', gap: '8px' }}>
                  <Clock size={15} style={{ color: '#e65100' }} />
                  {calculateArrivalTime(departureTime, durationHours, durationMinutes).display}
                </div>
              </div>
              
              <div className="form-group">
                <label className="form-label" style={{ color: '#9ca3af' }}>Fare per Seat (LKR)</label>
                <div style={{ position: 'relative' }}>
                  <span style={{ position: 'absolute', left: '12px', top: '12px', color: '#e65100', fontWeight: 'bold' }}>Rs.</span>
                  <input type="number" className="form-input" style={{ backgroundColor: '#1e293b', color: 'white', border: '1px solid rgba(255,255,255,0.1)', paddingLeft: '40px' }} min="100" max="10000" value={price} onChange={(e) => setPrice(e.target.value)} required />
                </div>
              </div>

              <div className="form-group">
                <label className="form-label" style={{ color: '#9ca3af' }}>Frequency Pattern</label>
                <CustomSelect
                  options={[
                    { value: 'daily', label: 'Daily Schedule' },
                    { value: 'weekdays', label: 'Weekdays Only (Mon-Fri)' },
                    { value: 'weekends', label: 'Weekends Only (Sat-Sun)' },
                    { value: 'custom', label: 'Custom Days Selection' }
                  ]}
                  value={scheduleType}
                  onChange={setScheduleType}
                />
              </div>

              {scheduleType === 'custom' && (
                <div className="form-group">
                  <label className="form-label" style={{ color: '#9ca3af' }}>Days of Week</label>
                  <div style={{ display: 'flex', flexWrap: 'wrap', gap: '8px' }}>
                    {DAYS_OF_WEEK.map(day => {
                      const isSelected = customDays.includes(day.value);
                      return (
                        <button
                          key={day.value}
                          type="button"
                          onClick={() => toggleCustomDay(day.value)}
                          style={{
                            padding: '6px 12px',
                            borderRadius: '8px',
                            fontSize: '12px',
                            fontWeight: 600,
                            cursor: 'pointer',
                            border: '1px solid',
                            borderColor: isSelected ? 'var(--color-primary)' : 'rgba(255,255,255,0.1)',
                            backgroundColor: isSelected ? 'rgba(230, 81, 0, 0.2)' : '#1e293b',
                            color: isSelected ? 'white' : '#9ca3af',
                            transition: 'var(--transition-smooth)'
                          }}
                        >
                          {day.label}
                        </button>
                      );
                    })}
                  </div>
                </div>
              )}

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                <div className="form-group">
                  <label className="form-label" style={{ color: '#9ca3af' }}>Effective From</label>
                  <CustomDatePicker value={effectiveFrom} onChange={setEffectiveFrom} />
                </div>
                <div className="form-group">
                  <label className="form-label" style={{ color: '#9ca3af' }}>Effective Until</label>
                  <CustomDatePicker value={effectiveUntil} onChange={setEffectiveUntil} />
                </div>
              </div>

              <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '12px', marginTop: '24px' }}>
                <button type="button" className="btn-secondary" onClick={() => { setShowScheduleModal(false); }} style={{ padding: '8px 16px', background: 'transparent', border: '1px solid rgba(255,255,255,0.1)', color: '#9ca3af' }}>Cancel</button>
                <button type="submit" className="btn-primary" disabled={submitting} style={{ padding: '8px 20px', width: 'auto', marginTop: 0 }}>
                  {submitting ? 'Saving...' : 'Save Schedule'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* OVERRIDES MODAL */}
      {showOverrideModal && selectedSchedule && (
        <div className="modal-backdrop" style={{ position: 'fixed', top: 0, left: 0, right: 0, bottom: 0, backgroundColor: 'rgba(0,0,0,0.5)', display: 'flex', justifyContent: 'center', alignItems: 'center', zIndex: 1000 }}>
          <div className="table-card" style={{ width: '600px', background: '#0f172a', border: '1px solid rgba(255,255,255,0.1)', padding: '24px', borderRadius: '16px', maxHeight: '90vh', overflowY: 'auto' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
              <h3 style={{ margin: 0, fontSize: '18px', color: 'white' }}>Bus Swap / Overrides</h3>
              <button 
                type="button" 
                onClick={() => setShowOverrideModal(false)}
                style={{ background: 'none', border: 'none', color: '#9ca3af', fontSize: '20px', cursor: 'pointer' }}
              >
                &times;
              </button>
            </div>
            
            <div style={{ 
              backgroundColor: 'rgba(230, 81, 0, 0.1)', 
              border: '1px solid rgba(230, 81, 0, 0.2)', 
              borderRadius: '10px', 
              padding: '12px', 
              marginBottom: '20px',
              fontSize: '13px',
              color: '#f97316'
            }}>
              <strong>Route:</strong> {selectedSchedule.route?.origin} to {selectedSchedule.route?.destination} <br/>
              <strong>Default Bus:</strong> {selectedSchedule.vehicle?.name} ({selectedSchedule.vehicle?.registration_number}) at {selectedSchedule.departure_time.substring(0, 5)}
            </div>

            {/* Create Override Form */}
            <form onSubmit={handleAddOverride} style={{ borderBottom: '1px solid rgba(255,255,255,0.1)', paddingBottom: '20px', marginBottom: '20px' }}>
              <h4 style={{ color: 'white', fontSize: '14px', marginBottom: '12px' }}>Apply a Temporary Bus Swap</h4>
              {overrideError && <div style={{ color: '#ef4444', marginBottom: '12px', fontSize: '13px' }}>{overrideError}</div>}
              
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px', marginBottom: '12px' }}>
                <div className="form-group" style={{ marginBottom: 0 }}>
                  <label className="form-label" style={{ color: '#9ca3af', fontSize: '11px' }}>Swap Date</label>
                  <CustomDatePicker value={overrideDate} onChange={setOverrideDate} />
                </div>
                <div className="form-group" style={{ marginBottom: 0 }}>
                  <label className="form-label" style={{ color: '#9ca3af', fontSize: '11px' }}>Replacement Bus</label>
                  <CustomSelect
                    options={vehicles.filter(v => v.id !== selectedSchedule.vehicle_id).map(v => ({ value: v.id, label: `${v.name} (${v.registration_number})` }))}
                    value={overrideVehicleId}
                    onChange={setOverrideVehicleId}
                    placeholder="-- Choose Replacement --"
                  />
                </div>
              </div>

              <div className="form-group" style={{ marginBottom: '16px' }}>
                <label className="form-label" style={{ color: '#9ca3af', fontSize: '11px' }}>Reason (Optional)</label>
                <input 
                  type="text" 
                  className="form-input" 
                  style={{ backgroundColor: '#1e293b', color: 'white', border: '1px solid rgba(255,255,255,0.1)', padding: '10px' }} 
                  placeholder="e.g. Bus undergoing periodic servicing" 
                  value={overrideReason} 
                  onChange={(e) => setOverrideReason(e.target.value)} 
                />
              </div>

              <button type="submit" className="btn-primary" disabled={submitting} style={{ padding: '10px 18px', width: 'auto', marginTop: 0 }}>
                {submitting ? 'Applying...' : 'Apply Swap'}
              </button>
            </form>

            {/* List Existing Overrides */}
            <div>
              <h4 style={{ color: 'white', fontSize: '14px', marginBottom: '12px' }}>Active Swaps</h4>
              {loadingOverrides ? (
                <div style={{ color: '#9ca3af', fontSize: '13px', textAlign: 'center', padding: '10px' }}>Loading swaps...</div>
              ) : overrides.length === 0 ? (
                <div style={{ color: '#64748b', fontSize: '13px', fontStyle: 'italic', textAlign: 'center', padding: '10px' }}>
                  No bus swaps scheduled for this route.
                </div>
              ) : (
                <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
                  {overrides.map(o => (
                    <div 
                      key={o.id} 
                      style={{ 
                        display: 'flex', 
                        justifyContent: 'space-between', 
                        alignItems: 'center', 
                        backgroundColor: '#1e293b', 
                        padding: '10px 14px', 
                        borderRadius: '8px',
                        border: '1px solid rgba(255,255,255,0.05)'
                      }}
                    >
                      <div>
                        <div style={{ color: 'white', fontWeight: 600, fontSize: '13.5px' }}>
                          Date: {o.override_date}
                        </div>
                        <div style={{ color: '#e65100', fontSize: '12.5px', marginTop: '2px', fontWeight: 500 }}>
                          Replaced with: {o.replacement_vehicle?.name} ({o.replacement_vehicle?.registration_number})
                        </div>
                        {o.reason && (
                          <div style={{ color: '#9ca3af', fontSize: '12px', marginTop: '2px', fontStyle: 'italic' }}>
                            Reason: "{o.reason}"
                          </div>
                        )}
                      </div>
                      <button 
                        type="button" 
                        onClick={() => handleDeleteOverride(o.id)}
                        style={{ background: 'none', border: 'none', color: '#ef4444', cursor: 'pointer', padding: '6px' }}
                        title="Cancel Swap"
                      >
                        <Trash2 size={16} />
                      </button>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
