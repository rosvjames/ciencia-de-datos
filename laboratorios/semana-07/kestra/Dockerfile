FROM kestra/kestra:v1.3.37

USER root

# Python + dbt-snowflake en un venv aislado para ejecutar dbt con el task runner Process
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 python3-venv \
    && rm -rf /var/lib/apt/lists/* \
    && python3 -m venv /opt/dbt \
    && /opt/dbt/bin/pip install --no-cache-dir "dbt-core~=1.12.0" "dbt-snowflake~=1.12.0"

ENV PATH="/opt/dbt/bin:${PATH}"
