# Lambda deployment stage
ARG PYTHON_VERSION=3.12
FROM public.ecr.aws/lambda/python:${PYTHON_VERSION} AS lambda-python

# Install dependencies for Lambda
COPY requirements.txt .
RUN pip install -r requirements.txt --target "${LAMBDA_TASK_ROOT}"

# Copy function code
COPY lambda_function.py ${LAMBDA_TASK_ROOT}

# Set the handler
CMD ["lambda_function.lambda_handler"]

# Development environment stage
FROM public.ecr.aws/amazonlinux/amazonlinux:2023 AS al2023-python
ARG PYTHON_VERSION=3.12

# Install system dependencies and Python
RUN dnf install -y git tar gcc jq make \
    zlib-devel bzip2-devel readline-devel \
    sqlite sqlite-devel openssl-devel \
    tk-devel libffi-devel xz-devel aws-cli && \
    curl https://pyenv.run | bash && \
    echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.bashrc && \
    echo 'export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc && \
    echo 'eval "$(pyenv init -)"' >> ~/.bashrc && \
    source ~/.bashrc && \
    pyenv install ${PYTHON_VERSION} && \
    pyenv global ${PYTHON_VERSION} && \
    python -m ensurepip --upgrade && \
    pip install --upgrade pip

# Set working directory
WORKDIR /var/task