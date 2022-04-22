pkglib_LTLIBRARIES=srv_stego_wiper.la

AM_CPPFLAGS=-I$(top_srcdir)/ -I$(top_srcdir)/include/ -I$(top_builddir)/include/

srv_stego_wiper_la_LIBADD = @MODULES_LIBADD@
#srv_stego_wiper_la_CFLAGS=  @MODULES_CFLAGS@
srv_stego_wiper_la_LDFLAGS= -module -avoid-version
srv_stego_wiper_la_SOURCES = srv_stego_wiper.c

#EXTRA_DIST= makefile.w32 srv_stego_wiper.def
