import os
import random
import string

import psycopg
from flask import Flask, render_template, request

DATABASE_URL = os.environ['DATABASE_URL']
LOCALES = [('en_US', 'United States (en_US)'), ('de_DE', 'Germany (de_DE)')]
BATCH = 10

app = Flask(__name__)


def fetch_users(locale, seed, page, count=BATCH):
    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute(
            'SELECT row_no, full_name, address, latitude, longitude,'
            '       height_cm, weight_kg, eye_color, phone, email'
            '  FROM generate_users(%s, %s, %s, %s)',
            (locale, seed, page, count))
        columns = [c.name for c in cur.description]
        return [dict(zip(columns, row)) for row in cur.fetchall()]


def random_seed():
    return ''.join(random.choices(string.ascii_lowercase + string.digits, k=8))


@app.route('/')
def index():
    locale = request.args.get('locale', LOCALES[0][0])
    seed = request.args.get('seed') or random_seed()
    page = max(1, request.args.get('page', type=int, default=1))

    if locale not in dict(LOCALES):
        locale = LOCALES[0][0]

    return render_template(
        'index.html',
        users=fetch_users(locale, seed, page),
        locales=LOCALES, locale=locale, seed=seed, page=page, batch=BATCH)


if __name__ == '__main__':
    app.run(debug=True, port=5000)
