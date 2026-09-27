#!/usr/bin/env python3
"""Validate public commerce configuration before building; never reads credentials."""
import argparse
import json
from pathlib import Path
from urllib.parse import urlparse


def problems(config, production=False):
    errors = []
    for key in ('storeID', 'productID', 'variantID', 'deviceLimit'):
        if type(config.get(key)) is not int or config[key] <= 0:
            errors.append(f'{key} must be a positive integer')
    if type(config.get('testMode')) is not bool:
        errors.append('testMode must be explicitly true or false')
    if production and config.get('testMode') is not False:
        errors.append('Production release blocked: Lemon Squeezy is still configured for TEST mode')
    url = urlparse(config.get('checkoutURL', ''))
    if (url.scheme != 'https' or not (url.hostname or '').endswith('.lemonsqueezy.com')
            or url.username or url.password or not url.path.startswith('/checkout/buy/')):
        errors.append('checkoutURL must be a public HTTPS Lemon Squeezy checkout/buy URL')
    if not isinstance(config.get('priceLabel'), str) or not config['priceLabel'].strip():
        errors.append('priceLabel is required')
    return errors


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--production', action='store_true')
    parser.add_argument('--config', type=Path, default=Path(__file__).resolve().parents[1] / 'config/Commerce.json')
    args = parser.parse_args()
    errors = problems(json.loads(args.config.read_text()), args.production)
    if errors:
        raise SystemExit('\n'.join(errors))
    print('PASS: production configuration checks' if args.production else 'PASS: candidate configuration checks')
