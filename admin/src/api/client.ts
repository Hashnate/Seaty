const API_BASE = '/api/v1';

interface RequestOptions {
  method?: string;
  body?: unknown;
  token?: string;
}

async function request<T>(endpoint: string, options: RequestOptions = {}): Promise<T> {
  const { method = 'GET', body, token } = options;
  
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
  };
  
  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
  }

  const config: RequestInit = {
    method,
    headers,
  };
  
  if (body && method !== 'GET') {
    config.body = JSON.stringify(body);
  }

  const response = await fetch(`${API_BASE}${endpoint}`, config);
  
  if (!response.ok) {
    const errorData = await response.json().catch(() => ({ detail: 'Request failed' }));
    throw new Error(errorData.detail || `HTTP ${response.status}`);
  }

  if (response.status === 204) {
    return {} as T;
  }
  
  return response.json();
}

// ==========================================
// Auth
// ==========================================
export async function loginAdmin(email: string, password: string) {
  const formData = new URLSearchParams();
  formData.append('username', email);
  formData.append('password', password);
  
  const response = await fetch(`${API_BASE}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: formData,
  });
  
  if (!response.ok) {
    const err = await response.json().catch(() => ({ detail: 'Login failed' }));
    throw new Error(err.detail);
  }
  return response.json();
}

export async function getCurrentUser(token: string) {
  return request('/auth/me', { token });
}

/** Creates an operator (owner) account. Admin only — the endpoint rejects any
 *  other role, and pins the created account to "owner". */
export async function registerUser(token: string, data: Record<string, unknown>) {
  const response = await fetch(`${API_BASE}/auth/register`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(data),
  });
  if (!response.ok) {
    const err = await response.json().catch(() => ({ detail: 'Registration failed' }));
    throw new Error(err.detail || 'Failed to register account');
  }
  return response.json();
}

// ==========================================
// Admin Dashboard
// ==========================================
export async function getDashboardStats(token: string) {
  return request('/admin/dashboard', { token });
}

export async function getRevenueAnalytics(token: string, days = 30) {
  return request(`/admin/analytics/revenue?days=${days}`, { token });
}

export async function getPlatformSettings(token: string) {
  return request('/admin/settings', { token });
}

export async function updatePlatformSetting(token: string, key: string, value: string) {
  return request(`/admin/settings/${key}`, {
    method: 'PUT',
    body: { value },
    token,
  });
}

// ==========================================
// Bus Companies
// ==========================================
export async function getCompanies(token: string) {
  return request('/companies', { token });
}

export async function getCompanyDetail(token: string, companyId: string) {
  return request(`/companies/${companyId}`, { token });
}

export async function createCompany(token: string, data: Record<string, unknown>) {
  return request('/companies', { method: 'POST', body: data, token });
}

export async function updateCompany(token: string, companyId: string, data: Record<string, unknown>) {
  return request(`/companies/${companyId}`, { method: 'PATCH', body: data, token });
}

export async function toggleCompanyStatus(token: string, companyId: string) {
  return request(`/companies/${companyId}/toggle`, { method: 'PATCH', token });
}

// ==========================================
// Vehicles
// ==========================================
export async function getVehicles(token: string) {
  return request('/vehicles', { token });
}

export async function approveVehicle(token: string, vehicleId: string) {
  return request(`/vehicles/${vehicleId}/approve`, { method: 'POST', token });
}

export async function rejectVehicle(token: string, vehicleId: string) {
  return request(`/vehicles/${vehicleId}/reject`, { method: 'POST', token });
}

// ==========================================
// Bookings
// ==========================================
export async function getBookings(token: string) {
  return request('/bookings', { token });
}

export async function getBooking(token: string, bookingId: string) {
  return request(`/bookings/${bookingId}`, { token });
}

// ==========================================
// Trips
// ==========================================
export async function getTrips(token: string, date?: string) {
  const query = date ? `?date=${date}` : '';
  return request(`/trips${query}`, { token });
}

// ==========================================
// Payments
// ==========================================
export async function refundPayment(token: string, paymentId: string) {
  return request(`/payments/${paymentId}/refund`, { method: 'POST', token });
}

// ==========================================
// Users
// ==========================================
export async function getUsers(token: string, role?: string) {
  const query = role ? `?role=${role}` : '';
  return request(`/admin/users${query}`, { token });
}

// ==========================================
// Routes Templates
// ==========================================
export async function getRoutes(token: string) {
  return request('/routes', { token });
}

export async function createRoute(token: string, data: Record<string, unknown>) {
  return request('/routes', { method: 'POST', body: data, token });
}

export async function deleteRoute(token: string, routeId: string) {
  return request(`/routes/${routeId}`, { method: 'DELETE', token });
}

// ==========================================
// Vehicle Management (Owner/Admin)
// ==========================================
export async function createVehicle(token: string, data: Record<string, unknown>) {
  return request('/vehicles', { method: 'POST', body: data, token });
}

export async function deleteVehicle(token: string, vehicleId: string) {
  return request(`/vehicles/${vehicleId}`, { method: 'DELETE', token });
}

export async function updateVehicle(token: string, vehicleId: string, data: Record<string, unknown>) {
  return request(`/vehicles/${vehicleId}`, { method: 'PUT', body: data, token });
}

// ==========================================
// Trip Management (Owner/Admin)
// ==========================================
export async function createTrip(token: string, data: Record<string, unknown>) {
  return request('/trips', { method: 'POST', body: data, token });
}

export async function deleteTrip(token: string, tripId: string) {
  return request(`/trips/${tripId}`, { method: 'DELETE', token });
}

export async function updateTrip(token: string, tripId: string, data: Record<string, unknown>) {
  return request(`/trips/${tripId}`, { method: 'PUT', body: data, token });
}

// Conductor/Staff Management (Owner)
// ==========================================
export async function getConductors(token: string) {
  return request('/conductors', { token });
}

export async function createConductor(token: string, data: Record<string, unknown>) {
  return request('/conductors', { method: 'POST', body: data, token });
}

export async function deleteConductor(token: string, conductorId: string) {
  return request(`/conductors/${conductorId}`, { method: 'DELETE', token });
}

// ==========================================
// Notifications
// ==========================================
export async function getNotifications(token: string) {
  return request('/notifications', { token });
}

export async function markNotificationRead(token: string, id: string) {
  return request(`/notifications/${id}/read`, { method: 'POST', token });
}

export async function markAllNotificationsRead(token: string) {
  return request('/notifications/read-all', { method: 'POST', token });
}

export async function broadcastNotification(token: string, title: string, message: string, targetRole: string) {
  return request('/notifications/broadcast', {
    method: 'POST',
    body: { title, message, target_role: targetRole },
    token,
  });
}

export async function sendDirectNotification(token: string, payload: { phone_number?: string; user_id?: string; title: string; message: string }) {
  return request('/notifications/send-direct', {
    method: 'POST',
    body: payload,
    token,
  });
}

export async function getFcmStatus(token: string) {
  return request('/notifications/fcm-status', { token });
}


// ==========================================
// Recurring Trip Schedules (Owner/Admin)
// ==========================================
export async function getSchedules(token: string) {
  return request('/schedules', { token });
}

export async function createSchedule(token: string, data: Record<string, unknown>) {
  return request('/schedules', { method: 'POST', body: data, token });
}

export async function updateSchedule(token: string, scheduleId: string, data: Record<string, unknown>) {
  return request(`/schedules/${scheduleId}`, { method: 'PUT', body: data, token });
}

export async function deleteSchedule(token: string, scheduleId: string) {
  return request(`/schedules/${scheduleId}`, { method: 'DELETE', token });
}

export async function toggleSchedule(token: string, scheduleId: string) {
  return request(`/schedules/${scheduleId}/toggle`, { method: 'PATCH', token });
}

// ==========================================
// Bus Overrides
// ==========================================
export async function getScheduleOverrides(token: string, scheduleId: string) {
  return request(`/schedules/${scheduleId}/overrides`, { token });
}

export async function createScheduleOverride(token: string, scheduleId: string, data: Record<string, unknown>) {
  return request(`/schedules/${scheduleId}/overrides`, { method: 'POST', body: data, token });
}

export async function deleteScheduleOverride(token: string, overrideId: string) {
  return request(`/schedules/overrides/${overrideId}`, { method: 'DELETE', token });
}

export async function changePassword(token: string, data: Record<string, unknown>) {
  return request('/auth/change-password', {
    method: 'POST',
    body: data,
    token,
  });
}

// ==========================================
// Image File Uploads
// ==========================================
export async function uploadVehicleMainImage(token: string, file: File) {
  const formData = new FormData();
  formData.append('file', file);

  const response = await fetch(`${API_BASE}/uploads/vehicle-main-image`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
    body: formData,
  });

  if (!response.ok) {
    const err = await response.json().catch(() => ({ detail: 'Failed to upload image' }));
    throw new Error(err.detail || 'Image upload failed');
  }

  return response.json();
}

export async function uploadVehicleGallery(token: string, files: File[]) {
  const formData = new FormData();
  files.forEach(file => formData.append('files', file));

  const response = await fetch(`${API_BASE}/uploads/vehicle-gallery`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
    body: formData,
  });

  if (!response.ok) {
    const err = await response.json().catch(() => ({ detail: 'Failed to upload gallery images' }));
    throw new Error(err.detail || 'Gallery upload failed');
  }

  return response.json();
}



// ==========================================
// Hero Banners (Passenger home carousel - Admin managed)
// ==========================================
export interface HeroBanner {
  id: string;
  image_url: string;
  title: string | null;
  subtitle: string | null;
  sort_order: number;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

/** Admin console listing - includes banners hidden from the app. */
export async function getBanners(token: string) {
  return request<HeroBanner[]>('/banners?include_inactive=true', { token });
}

export async function createBanner(token: string, data: Record<string, unknown>) {
  return request<HeroBanner>('/banners', { method: 'POST', body: data, token });
}

export async function updateBanner(token: string, bannerId: string, data: Record<string, unknown>) {
  return request<HeroBanner>(`/banners/${bannerId}`, { method: 'PATCH', body: data, token });
}

export async function deleteBanner(token: string, bannerId: string) {
  return request<void>(`/banners/${bannerId}`, { method: 'DELETE', token });
}

export async function uploadBannerImage(token: string, file: File) {
  const formData = new FormData();
  formData.append('file', file);

  const response = await fetch(`${API_BASE}/uploads/banner`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
    body: formData,
  });

  if (!response.ok) {
    const err = await response.json().catch(() => ({ detail: 'Failed to upload banner image' }));
    throw new Error(err.detail || 'Banner image upload failed');
  }

  return response.json() as Promise<{ url: string; filename: string }>;
}
