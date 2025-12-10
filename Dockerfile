# Grasshopper Container - Open Source BACnet Network Visualization
# https://github.com/ACE-IoT-Solutions/grasshopper

FROM python:3.10-slim AS volttron-base

ENV VOLTTRON_USER_HOME=/home/volttron
ENV VOLTTRON_HOME=${VOLTTRON_USER_HOME}/.grasshopper-volttron
ENV CODE_ROOT=/code
ENV VOLTTRON_ROOT=${CODE_ROOT}/volttron

USER root

# Install system dependencies and UV
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    python3-dev \
    libssl-dev \
    libffi-dev \
    libzmq3-dev \
    git \
    curl \
    ca-certificates \
    procps \
    && rm -rf /var/lib/apt/lists/* \
    && curl -LsSf https://astral.sh/uv/install.sh | sh

# Add UV to PATH
ENV PATH="/root/.local/bin:${PATH}"

# Create volttron user
RUN useradd -m -s /bin/bash volttron

# Copy Volttron source from dependencies
COPY deps/volttron ${VOLTTRON_ROOT}
WORKDIR ${VOLTTRON_ROOT}

# Install dependencies using UV (wheel 0.30 required by Volttron)
RUN uv pip install --system 'wheel==0.30.0' setuptools && \
    uv pip install --system \
        'gevent==24.2.1' \
        'grequests==0.7.0' \
        'requests==2.31.0' \
        'idna<3,>=2.5' \
        'ply==3.11' \
        'psutil==5.9.1' \
        'python-dateutil==2.8.2' \
        'pytz==2022.1' \
        'PyYAML==6.0' \
        'setuptools>=40.0.0,<=70.0.0' \
        'tzlocal==2.1' \
        'cryptography==37.0.4' \
        'watchdog<5.0' \
        'watchdog-gevent==0.1.1' \
        'deprecated==1.2.14' && \
    uv pip install --system 'pyzmq==26.0.2' --config-settings="--zmq=bundled"

# Install web dependencies
RUN uv pip install --system \
    'ws4py==0.5.1' \
    'PyJWT==1.7.1' \
    'Jinja2==3.1.2' \
    'passlib==1.7.4' \
    'argon2-cffi==21.3.0' \
    'Werkzeug==2.2.1' \
    'treelib==1.6.1'

# Install VOLTTRON
ENV PYTHONPATH=${VOLTTRON_ROOT}:${PYTHONPATH}
RUN uv pip install --system -e .

# Install Grasshopper dependencies
RUN /root/.local/bin/uv pip install --system \
    rdflib>=7.0.0 \
    pydantic>=2.6.4 \
    pyvis>=0.3.2 \
    fastapi>=0.110.0 \
    uvicorn>=0.27.1 \
    bacpypes3>=0.0.91

# Build Grasshopper frontend
# Install Node.js for building the Vue frontend
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Copy grasshopper repo and build frontend
COPY deps/grasshopper /code/grasshopper-repo
WORKDIR /code/grasshopper-repo/grasshopper-frontend
# Set API URL to empty string so frontend uses relative URLs
ENV VITE_FLIGHT_DECK_API_URL=""
RUN npm ci && \
    npm run build

# Copy Grasshopper agent (frontend build copied static files to Grasshopper/grasshopper/dist)
WORKDIR /code/grasshopper-repo/Grasshopper
RUN /root/.local/bin/uv pip install --system .

# Setup permissions
RUN mkdir -p ${VOLTTRON_HOME} ${VOLTTRON_HOME}/certificates ${VOLTTRON_HOME}/run && \
    chown -R volttron:volttron ${VOLTTRON_HOME} ${CODE_ROOT}

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER volttron
WORKDIR ${VOLTTRON_USER_HOME}

# Expose Grasshopper web UI port (default 5000)
EXPOSE 5000

# BACnet/IP port (47808) - exposed for reference but typically use host networking
EXPOSE 47808/udp

CMD ["/entrypoint.sh"]
