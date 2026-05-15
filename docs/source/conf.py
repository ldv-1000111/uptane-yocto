# docs/source/conf.py
# Sphinx configuration for Uptane OTA Implementation Guide
# Hosted on ReadTheDocs: https://readthedocs.org

import os
import sys

# -- Project information -------------------------------------------------------
project   = 'Uptane OTA Implementation Guide'
copyright = '2025, OTA Engineering Team'
author    = 'Luis Viveros'
release   = '1.0.0'
version   = '1.0'

# -- General configuration -----------------------------------------------------
extensions = [
    'sphinx.ext.autodoc',
    'sphinx.ext.viewcode',
    'sphinx.ext.githubpages',
    'sphinx.ext.intersphinx',
    'sphinx_copybutton',        # adds copy button to code blocks
    'myst_parser',              # enables .md files alongside .rst
]

# Source file suffixes
source_suffix = {
    '.rst': 'restructuredtext',
    '.md':  'markdown',
}

templates_path = ['_templates']
exclude_patterns = ['_build', 'Thumbs.db', '.DS_Store']
master_doc = 'index'

# -- MyST parser options (for .md files) ---------------------------------------
myst_enable_extensions = [
    'colon_fence',
    'deflist',
    'tasklist',
]

# -- HTML output — Read the Docs Sphinx Theme ----------------------------------
html_theme = 'sphinx_rtd_theme'

html_theme_options = {
    'logo_only':            False,
    'navigation_depth':     4,
    'collapse_navigation':  False,
    'sticky_navigation':    True,
    'includehidden':        True,
    'titles_only':          False,
    'style_external_links': True,
    'prev_next_buttons_location': 'both',
}

html_static_path = ['_static']
html_css_files   = ['custom.css']

html_title = 'Uptane OTA Implementation Guide'
html_short_title = 'Uptane OTA'

# -- Copy button config --------------------------------------------------------
copybutton_prompt_text = r'^\$ |^>>> '
copybutton_prompt_is_regexp = True

# -- Intersphinx ---------------------------------------------------------------
intersphinx_mapping = {
    'python': ('https://docs.python.org/3', None),
}

# -- ReadTheDocs environment detection ----------------------------------------
on_rtd = os.environ.get('READTHEDOCS', None) == 'True'
