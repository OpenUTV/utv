#import "../../common/manual-lib.typ": *
#show: manual.with(appendix: true)

= Crash Reporting <app-crash-reporting>

#app includes Google's crash reporting mechanism called Breakpad on Linux. If
#app crashes it will produce a file in `/tmp` with an extension of `.dmp`.
