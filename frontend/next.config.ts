import type { NextConfig } from "next";

// Allow HMR WebSocket connections from additional origins in dev mode.
// Set NEXT_PUBLIC_ALLOWED_DEV_ORIGINS to a comma-separated list of IPs/hostnames
// (e.g. "20.29.102.93" for the Azure Application Gateway public IP).
const allowedDevOrigins = process.env.NEXT_PUBLIC_ALLOWED_DEV_ORIGINS
  ? process.env.NEXT_PUBLIC_ALLOWED_DEV_ORIGINS.split(",").map((o) => o.trim())
  : [];

const nextConfig: NextConfig = {
  experimental: {
    allowedDevOrigins,
  },
};

export default nextConfig;
