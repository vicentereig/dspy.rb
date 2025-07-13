# Use official Ruby image
FROM ruby:3.2-slim

# Install dependencies for Playwright and build tools
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    git \
    unzip \
    # Dependencies for Chromium
    libnss3 \
    libnspr4 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libdbus-1-3 \
    libatspi2.0-0 \
    libx11-6 \
    libxcomposite1 \
    libxdamage1 \
    libxext6 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libxcb1 \
    libxkbcommon0 \
    libpango-1.0-0 \
    libcairo2 \
    libasound2 \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Install Bun
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:$PATH"

# Copy Gemfile and package.json first for better caching
COPY Gemfile Gemfile.lock ./
COPY package.json bun.lockb ./

# Install Ruby dependencies
RUN bundle install

# Install Node dependencies
RUN bun install

# Install Playwright and browsers
RUN bunx playwright install chromium

# Copy the rest of the application
COPY . .

# Build the site
CMD ["bun", "run", "build"]