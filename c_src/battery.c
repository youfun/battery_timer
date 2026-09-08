/*
 * Project-owned battery NIF. Mob's Android device_battery_state is still
 * TODO(unknown/-1); this calls MobBridge.batterySnapshot() instead.
 */

#include <erl_nif.h>
#include <stdlib.h>
#include <string.h>

#ifdef __ANDROID__
#include <jni.h>

extern JavaVM *g_jvm;
extern jclass g_app_bridge_cls;

static JNIEnv *jni_env(int *attached) {
    JNIEnv *env = NULL;

    *attached = 0;
    if (g_jvm == NULL) return NULL;
    if ((*g_jvm)->GetEnv(g_jvm, (void **)&env, JNI_VERSION_1_6) == JNI_OK) return env;
    if ((*g_jvm)->AttachCurrentThread(g_jvm, &env, NULL) != JNI_OK) return NULL;
    *attached = 1;
    return env;
}

static void jni_release(int attached) {
    if (attached && g_jvm != NULL) (*g_jvm)->DetachCurrentThread(g_jvm);
}

static int jni_failed(JNIEnv *env) {
    if ((*env)->ExceptionCheck(env)) {
        (*env)->ExceptionDescribe(env);
        (*env)->ExceptionClear(env);
        return 1;
    }
    return 0;
}

static ERL_NIF_TERM parse_snapshot(ErlNifEnv *env, const char *s) {
    const char *bar;
    char state[16];
    int percent = -1;
    size_t n;

    bar = strchr(s, '|');
    if (bar == NULL) return enif_make_tuple2(env, enif_make_atom(env, "unknown"), enif_make_int(env, -1));

    n = (size_t)(bar - s);
    if (n >= sizeof(state)) n = sizeof(state) - 1;
    memcpy(state, s, n);
    state[n] = 0;
    percent = atoi(bar + 1);

    if (strcmp(state, "charging") != 0 && strcmp(state, "full") != 0 &&
        strcmp(state, "unplugged") != 0) {
        strcpy(state, "unknown");
    }

    return enif_make_tuple2(env, enif_make_atom(env, state), enif_make_int(env, percent));
}
#endif

static ERL_NIF_TERM status(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc;
    (void)argv;

#ifdef __ANDROID__
    int attached = 0;
    JNIEnv *jenv;
    jmethodID mid;
    jstring reply;
    const char *chars;
    ERL_NIF_TERM term;

    jenv = jni_env(&attached);
    if (jenv == NULL || g_app_bridge_cls == NULL) {
        jni_release(attached);
        return enif_make_tuple2(env, enif_make_atom(env, "unknown"), enif_make_int(env, -1));
    }

    mid = (*jenv)->GetStaticMethodID(jenv, g_app_bridge_cls, "batterySnapshot", "()Ljava/lang/String;");
    if (mid == NULL || jni_failed(jenv)) {
        jni_release(attached);
        return enif_make_tuple2(env, enif_make_atom(env, "unknown"), enif_make_int(env, -1));
    }

    reply = (jstring)(*jenv)->CallStaticObjectMethod(jenv, g_app_bridge_cls, mid);
    if (reply == NULL || jni_failed(jenv)) {
        jni_release(attached);
        return enif_make_tuple2(env, enif_make_atom(env, "unknown"), enif_make_int(env, -1));
    }

    chars = (*jenv)->GetStringUTFChars(jenv, reply, NULL);
    if (chars == NULL) {
        (*jenv)->DeleteLocalRef(jenv, reply);
        jni_release(attached);
        return enif_make_tuple2(env, enif_make_atom(env, "unknown"), enif_make_int(env, -1));
    }

    term = parse_snapshot(env, chars);
    (*jenv)->ReleaseStringUTFChars(jenv, reply, chars);
    (*jenv)->DeleteLocalRef(jenv, reply);
    jni_release(attached);
    return term;
#else
    return enif_make_tuple2(env, enif_make_atom(env, "unknown"), enif_make_int(env, -1));
#endif
}

static ErlNifFunc nif_funcs[] = {
    {"status", 0, status, 0}
};

ERL_NIF_INIT(Elixir.BatteryTimer.Nifs.Battery, nif_funcs, NULL, NULL, NULL, NULL)
