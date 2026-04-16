# libsignal ships consumer rules, but its SessionCipher bridge adapters still
# end up being aggressively optimized in our release build. Keep the native
# bridge entry points and the internal store contracts stable so session setup
# and pre-key processing keep working under R8.
-keep class org.signal.libsignal.protocol.SessionBuilder { *; }
-keep class org.signal.libsignal.protocol.SessionCipher { *; }
-keep class org.signal.libsignal.protocol.SessionCipher$* { *; }
-keep class org.signal.libsignal.internal.** { *; }
-keep class org.signal.libsignal.protocol.state.internal.** { *; }
-keep class org.signal.libsignal.protocol.state.impl.InMemorySignalProtocolStore { *; }
