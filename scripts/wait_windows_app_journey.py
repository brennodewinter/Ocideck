#!/usr/bin/env python3
"""Wait for this immutable commit's automatic Windows mirror journey, without secrets."""
import argparse
import json
import os
from pathlib import Path
import time
import urllib.error
import urllib.parse
import urllib.request

API = 'https://api.github.com/repos/brennodewinter/Ocideck'
WORKFLOW = 'windows-app-journey.yml'


def get(path):
    request = urllib.request.Request(API + path, headers={
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'OciDeck-app-journey',
    })
    with urllib.request.urlopen(request, timeout=45) as response:
        return json.load(response)


def matching_run(runs, sha, branch, event):
    rows = [r for r in runs if r.get('head_sha') == sha
            and r.get('head_branch') == branch and r.get('event') == event
            and r.get('path') == '.github/workflows/' + WORKFLOW]
    return max(rows, key=lambda row: row['id'], default=None)


def wait(sha, branch, full, evidence, timeout=9000, event=None):
    if len(sha) != 40 or any(c not in '0123456789abcdef' for c in sha):
        raise ValueError('Expected a full immutable commit SHA')
    evidence.mkdir(parents=True, exist_ok=True)
    event = event or ('schedule' if full else 'push')
    query = urllib.parse.urlencode(dict(head_sha=sha, branch=branch, event=event, per_page=30))
    deadline = time.monotonic() + timeout
    run = None
    while time.monotonic() < deadline:
        try:
            if run is None:
                data = get(f'/actions/workflows/{WORKFLOW}/runs?{query}')
                run = matching_run(data['workflow_runs'], sha, branch, event)
            else:
                run = get('/actions/runs/' + str(run['id']))
            if run is not None:
                # Revalidate the server response, including the trigger and workflow.
                if matching_run([run], sha, branch, event) is None:
                    raise RuntimeError('Windows run identity changed')
                (evidence / 'windows-run.json').write_text(json.dumps(run, indent=2) + '\n')
                print(run['html_url'], run['status'], run.get('conclusion'), flush=True)
                if run['status'] == 'completed':
                    if run.get('conclusion') != 'success':
                        raise RuntimeError('Windows app journey failed: ' + run['html_url'])
                    jobs = get('/actions/runs/' + str(run['id']) + '/jobs?per_page=100')['jobs']
                    (evidence / 'windows-jobs.json').write_text(json.dumps(jobs, indent=2) + '\n')
                    if (len(jobs) != 1 or jobs[0].get('conclusion') != 'success'
                            or jobs[0].get('name') != 'app-reis Windows (' + ('full' if full else 'short') + ')'):
                        raise RuntimeError('Missing or unsuccessful Windows app journey job')
                    return run
            else:
                print('Waiting for the automatic Windows mirror run: ' + sha, flush=True)
        except urllib.error.HTTPError as error:
            # Mirroring/first deployment and public API rate limiting may lag.
            if error.code not in {403, 404, 429, 500, 502, 503, 504}:
                raise
            print('Windows run lookup pending: HTTP ' + str(error.code), flush=True)
        except (TimeoutError, urllib.error.URLError) as error:
            print('Windows run lookup will retry: ' + str(error), flush=True)
        time.sleep(min(120, max(0, deadline - time.monotonic())))
    raise TimeoutError('No successful Windows journey for the exact source before the deadline')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--full', action='store_true')
    parser.add_argument('--event', choices=['push', 'schedule', 'workflow_dispatch'])
    args = parser.parse_args()
    wait(os.environ['JOURNEY_SHA'], os.environ['JOURNEY_BRANCH'], args.full,
         Path('build/app-journey/windows'), event=args.event)


if __name__ == '__main__':
    main()
