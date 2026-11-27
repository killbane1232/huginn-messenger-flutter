#!/usr/bin/env python3
"""Build the bundled frontend database from a version 1 sticker JSON export."""

import json
from pathlib import Path
import sqlite3
import sys


def main():
    source, destination = map(Path, sys.argv[1:])
    data = json.loads(source.read_text())
    if data['version'] != 1:
        raise ValueError('Unsupported sticker export version')
    # Never overwrite an existing database, including a user's live collection.
    with destination.open('xb'):
        pass
    with sqlite3.connect(destination) as db:
        db.executescript('''
            PRAGMA foreign_keys = ON;
            PRAGMA user_version = 1;
            CREATE TABLE frontend_metadata (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            CREATE TABLE sticker_categories (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL UNIQUE CHECK (length(trim(name)) > 0),
                position INTEGER NOT NULL UNIQUE
            );
            CREATE TABLE stickers (
                id INTEGER PRIMARY KEY,
                category_id INTEGER NOT NULL
                    REFERENCES sticker_categories(id) ON DELETE CASCADE,
                text TEXT NOT NULL CHECK (length(trim(text)) > 0),
                position INTEGER NOT NULL,
                UNIQUE (category_id, position)
            );
        ''')
        for position, category in enumerate(data['categories']):
            cursor = db.execute(
                'INSERT INTO sticker_categories (name, position) VALUES (?, ?)',
                (category['name'], position),
            )
            db.executemany(
                'INSERT INTO stickers (category_id, text, position) VALUES (?, ?, ?)',
                [(cursor.lastrowid, text, index)
                 for index, text in enumerate(category['stickers'])],
            )
        count = db.execute('SELECT count(*) FROM stickers').fetchone()[0]
    print(f'{destination}: {len(data["categories"])} folders, {count} stickers')


if __name__ == '__main__':
    main()
