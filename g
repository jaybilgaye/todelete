Great—Central GitLab is the cleanest option. Here are the exact steps to replace rsync with Git for your 2-host + MySQL Airflow setup.

Assumptions:

AIRFLOW_HOME=/app/airflow/airflow

DAGs path Airflow reads: /app/airflow/airflow/dags

GitLab repo: airflow-dags (private)

Branch: main

host1 = ACTIVE scheduler, host2 = standby scheduler

Webserver can run on both



---

1) Create the GitLab repo structure (once, in GitLab)

In your GitLab repo, keep:

airflow-dags/
  dags/
    *.py
  plugins/        (optional)
  README.md

Add a test DAG to verify end-to-end (dags/test_git_dag.py):

from datetime import datetime
from airflow import DAG
from airflow.operators.bash import BashOperator

with DAG(
    dag_id="test_git_dag",
    start_date=datetime(2024, 1, 1),
    schedule_interval=None,
    catchup=False,
    tags=["test"],
) as dag:
    BashOperator(task_id="print_date", bash_command="date")

Commit + push to main.


---

2) Install git on BOTH hosts

On host1 and host2:

sudo yum install -y git
git --version


---

3) Ensure Airflow uses the correct home (BOTH hosts)

As airflow:

sudo -iu airflow
echo 'export AIRFLOW_HOME=/app/airflow/airflow' >> ~/.bashrc
source ~/.bashrc
echo $AIRFLOW_HOME

Verify DB is MySQL (important):

airflow config get-value database sql_alchemy_conn

Must show mysql+...://...:3306/... (not sqlite).


---

4) Deploy DAGs from GitLab onto BOTH hosts (recommended safe layout)

We will:

Clone repo into /app/airflow/git/dags_repo

Point Airflow’s dags folder to repo’s dags/ via symlink (stable path)


4.1 Create clone directory (BOTH hosts)

sudo mkdir -p /app/airflow/git
sudo chown -R airflow:airflow /app/airflow/git

4.2 Clone repo (BOTH hosts)

As airflow:

sudo -iu airflow
cd /app/airflow/git
git clone <GITLAB_REPO_SSH_OR_HTTPS_URL> dags_repo

> If your GitLab is private, SSH is easiest (deploy key). See Step 5.



4.3 Point Airflow DAGs folder to the repo (BOTH hosts)

sudo rm -rf /app/airflow/airflow/dags
sudo ln -s /app/airflow/git/dags_repo/dags /app/airflow/airflow/dags
sudo chown -h airflow:airflow /app/airflow/airflow/dags

Verify:

ls -l /app/airflow/airflow/dags


---

5) Authentication to GitLab (pick ONE method)

Option A (Best): GitLab Deploy Key (SSH)

On each host, as airflow:

sudo -iu airflow
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
cat ~/.ssh/id_ed25519.pub

Add that public key in GitLab repo: Settings → Repository → Deploy keys → Add key (enable “write” only if that host will push; most of the time keep read-only)

Test:

ssh -T git@gitlab.yourcompany.com

Use SSH repo URL:

git@gitlab.yourcompany.com:group/airflow-dags.git

Option B: HTTPS + token (works, less clean)

Use GitLab personal access token and credential helper. (I can provide if you want.)


---

6) Automate updates with a safe git pull (BOTH hosts)

Create script:

sudo tee /usr/local/bin/airflow_git_update_dags.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd /app/airflow/git/dags_repo
git fetch --all --prune
git reset --hard origin/main
EOF
sudo chmod +x /usr/local/bin/airflow_git_update_dags.sh

Run once manually on both hosts:

sudo -iu airflow /usr/local/bin/airflow_git_update_dags.sh

Cron it (as airflow user) on both hosts:

sudo -iu airflow
crontab -e

Add:

* * * * * /usr/local/bin/airflow_git_update_dags.sh >> /app/airflow/airflow/logs/git_pull.log 2>&1


---

7) Scheduler HA (Active/Passive) operations

Normal state (host1 active)

On host1:

sudo systemctl enable --now airflow-scheduler
sudo systemctl enable --now airflow-webserver

On host2:

sudo systemctl stop airflow-scheduler
sudo systemctl enable --now airflow-webserver

If host1 goes down (manual failover)

On host2:

sudo systemctl start airflow-scheduler
sudo systemctl status airflow-scheduler --no-pager

Verify:

sudo -iu airflow airflow db check
curl -s http://localhost:8080/health

When host1 comes back

Keep host2 as active (simplest, avoids flapping):

sudo systemctl stop airflow-scheduler  # on host1


---

8) Verify DAG shows up

After adding test_git_dag.py in GitLab and waiting ~1 minute:

On active host:

sudo -iu airflow airflow dags list | grep test_git_dag

If not visible:

sudo -iu airflow airflow dags list-import-errors
sudo systemctl status airflow-scheduler --no-pager


---

What you’ve achieved

No rsync

Versioned DAG deployments

Rollbacks possible (git reset)

Both hosts always have identical DAGs

Single active scheduler prevents split-brain



---

If you paste your GitLab repo URL format you want to use (SSH or HTTPS), I’ll give you the exact clone command and the exact GitLab “Deploy key” steps for your domain (no guessing).