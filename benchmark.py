import os
import time

import psycopg

DATABASE_URL = os.environ['DATABASE_URL']


def measure(locale, seed, count):
    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        start = time.perf_counter()
        cur.execute('SELECT count(*) FROM generate_users(%s, %s, 1, %s)',
                    (locale, seed, count))
        cur.fetchone()
        return time.perf_counter() - start


if __name__ == '__main__':
    print(f"{'users':>9} {'seconds':>9} {'users/sec':>12}")
    for n in (1000, 10000, 50000, 100000):
        best = min(measure('en_US', 'bench', n) for _ in range(3))
        print(f'{n:>9,} {best:>9.2f} {n / best:>12,.0f}')
