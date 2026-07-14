const API_BASE = 'http://localhost:8000/api/v1';

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
export async function getTrips(token: string) {
  return request('/trips', { token });
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
