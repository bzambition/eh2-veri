#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""
EH2 Coverage Merge Script

Merges coverage databases from multiple test runs.
Modeled after ibex's merge_cov.py, adapted for EH2.
"""

import argparse
import logging
import os
import sys
from pathlib import Path
from typing import Set

from metadata import RegressionMetadata
from scripts_lib import run_one

logger = logging.getLogger(__name__)


def find_cov_dbs(start_dir: Path, simulator: str) -> Set[Path]:
    """Find all coverage databases under start_dir."""
    cov_dbs = set()

    if simulator == 'xlm':
        for p in start_dir.rglob('*.ucd'):
            logger.info(f'Found coverage database (ucd) at {p}')
            cov_dbs.add(p)
    elif simulator == 'vcs':
        for p in start_dir.rglob('test.vdb'):
            logger.info(f'Found coverage database (vdb) at {p}')
            cov_dbs.add(p)

    if not cov_dbs:
        logger.info(f'No coverage databases found for {simulator}')

    return cov_dbs


def merge_cov_vcs(md: RegressionMetadata, cov_dirs: Set[Path]) -> int:
    """Merge VCS coverage databases using urg."""
    cov_dir = Path(md.coverage_dir)
    cov_dir.mkdir(exist_ok=True, parents=True)

    cmd = [
        'urg', '-full64',
        '-format', 'both',
        '-dbname', str(cov_dir / 'merged.vdb'),
        '-report', str(cov_dir / 'report'),
        '-log', str(cov_dir / 'merge.log'),
        '-dir',
    ] + [str(d) for d in cov_dirs]

    stdout_log = cov_dir / 'merge_stdout.log'
    logger.info('Merging VCS coverage databases')
    return run_one(True, cmd, redirect_stdstreams=stdout_log)


def merge_cov_xlm(md: RegressionMetadata, cov_dbs: Set[Path]) -> int:
    """Merge Xcelium coverage databases using imc."""
    cov_dir = Path(md.coverage_dir)
    cov_dir.mkdir(exist_ok=True, parents=True)

    # Write database list to file
    db_list_file = cov_dir / 'cov_db_runfile'
    with open(db_list_file, 'w') as fd:
        fd.write('\n'.join(str(d.parent) for d in cov_dbs) + '\n')

    imc_cmd = [
        'imc', '-64bit',
        '-exec', 'merge',
        '-logfile', str(cov_dir / 'merge.log'),
    ]

    stdout_log = cov_dir / 'merge_stdout.log'
    logger.info('Merging Xcelium coverage databases')
    return run_one(True, imc_cmd, redirect_stdstreams=stdout_log)


def main():
    parser = argparse.ArgumentParser(description='Merge EH2 coverage databases')
    parser.add_argument('--dir-metadata', type=Path, required=True,
                        help='Path to regression metadata directory')
    args = parser.parse_args()

    md = RegressionMetadata.construct_from_metadata_dir(args.dir_metadata)

    if md.simulator not in ('vcs', 'xlm'):
        raise ValueError(f'Unsupported simulator for coverage merge: {md.simulator}')

    cov_dir = Path(md.coverage_dir)
    cov_dir.mkdir(exist_ok=True, parents=True)

    run_dir = Path(md.work_dir)
    cov_dbs = find_cov_dbs(run_dir, md.simulator)

    if not cov_dbs:
        logger.warning('No coverage databases found, skipping merge')
        return 0

    merge_funcs = {
        'vcs': merge_cov_vcs,
        'xlm': merge_cov_xlm,
    }
    return merge_funcs[md.simulator](md, cov_dbs)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except RuntimeError as err:
        sys.stderr.write(f'Error: {err}\n')
        sys.exit(1)
