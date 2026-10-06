project('singularity-help', ['vala', 'c'],
  version: '0.1.0',
  meson_version: '>= 0.59.0'
)

i18n = import('i18n')
add_project_arguments('-DGETTEXT_PACKAGE="singularity-help"', language: 'c')
subdir('po')

gtk_dep  = dependency('gtk4')
gee_dep  = dependency('gee-0.8')
xml_dep  = dependency('libxml-2.0')
pango_dep = dependency('pango')
gio_unix_dep = dependency('gio-unix-2.0')

libsingularity_dep = dependency('singularity-1.0',
  fallback: ['libsingularity', 'libsingularity_dep']
)

if not meson.is_subproject() and libsingularity_dep.type_name() == 'internal'
  libsingularity_vapi_dir = join_paths(meson.project_build_root(), 'subprojects', 'libsingularity')
  add_project_arguments(['--vapidir=' + libsingularity_vapi_dir], language: 'vala')
endif

core = files('src/document.vala', 'src/mallard.vala', 'src/library.vala')

executable('singularity-help',
  core + files('src/window.vala', 'src/search.vala', 'src/app.vala'),
  dependencies: [gtk_dep, gee_dep, xml_dep, gio_unix_dep, libsingularity_dep],
  install: true
)

help_test = executable('help-test',
  core + files('tests/help_test.vala'),
  dependencies: [gee_dep, xml_dep, pango_dep, gio_unix_dep],
)
test('help', help_test, env: ['HELP_FIXTURES=' + meson.current_source_dir() / 'tests' / 'fixtures', 'HELP_GUIDE=' + meson.current_source_dir() / 'guide'])

install_subdir('guide/C',
  install_dir: get_option('datadir') / 'singularity' / 'help'
)

install_data('data/dev.sinty.help.search-provider.ini',
  install_dir: get_option('datadir') / 'singularity' / 'search-providers',
  rename: 'dev.sinty.help.ini'
)

service_conf = configuration_data()
service_conf.set('bindir', get_option('prefix') / get_option('bindir'))
configure_file(
  input: 'data/dev.sinty.help.service.in',
  output: 'dev.sinty.help.service',
  configuration: service_conf,
  install_dir: get_option('datadir') / 'dbus-1' / 'services'
)

install_data('data/dev.sinty.help.desktop',
  install_dir: get_option('datadir') / 'applications'
)

install_data('data/icons/dev.sinty.help.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
)
