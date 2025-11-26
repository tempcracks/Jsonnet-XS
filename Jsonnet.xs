#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <stdlib.h>
#include <string.h>

#include "libjsonnet.h"

/* ---------- C-side wrapper object ---------- */

typedef struct PerlImportCtx {
    struct JsonnetVm *vm;
    PerlInterpreter  *perl;
    SV               *cb;   /* coderef */
} PerlImportCtx;

typedef struct NativeCtx {
    struct JsonnetVm *vm;
    PerlInterpreter  *perl;
    SV               *cb;      /* coderef */
    int               argc;
    char            **params;  /* NULL-terminated */
    struct NativeCtx *next;
} NativeCtx;

typedef struct PerlJsonnetVm {
    struct JsonnetVm *vm;
    PerlImportCtx    *import_ctx;
    NativeCtx        *native_head;
} PerlJsonnetVm;

/* ---------- helpers ---------- */

static void
free_import_ctx(PerlJsonnetVm *pvm) {
    if (pvm->import_ctx) {
#ifdef PERL_IMPLICIT_CONTEXT
        dTHXa(pvm->import_ctx->perl);
#else
        dTHX;
#endif
        SvREFCNT_dec(pvm->import_ctx->cb);
        Safefree(pvm->import_ctx);
        pvm->import_ctx = NULL;
    }
}

static void
free_native_ctxs(PerlJsonnetVm *pvm) {
    NativeCtx *cur = pvm->native_head;
    while (cur) {
        NativeCtx *nxt = cur->next;

        if (cur->params) {
            for (int i=0; cur->params[i]; i++) Safefree(cur->params[i]);
            Safefree(cur->params);
        }

#ifdef PERL_IMPLICIT_CONTEXT
        dTHXa(cur->perl);
#else
        dTHX;
#endif
        SvREFCNT_dec(cur->cb);

        Safefree(cur);
        cur = nxt;
    }
    pvm->native_head = NULL;
}

/* Perl import callback protocol:
   - on success: return ( $found_here, $content )
   - on failure: return ( undef, $errmsg )
*/
static int
perl_jsonnet_import_cb(void *vctx, const char *base, const char *rel,
                       char **found_here, char **buf, size_t *buflen)
{
    PerlImportCtx *ctx = (PerlImportCtx*)vctx;
#ifdef PERL_IMPLICIT_CONTEXT
    dTHXa(ctx->perl);
#else
    dTHX;
#endif
    dSP;

    int ok = 0;
    SV *cb = ctx->cb;

    ENTER; SAVETMPS;
    PUSHMARK(SP);
    XPUSHs(sv_2mortal(newSVpv(base, 0)));
    XPUSHs(sv_2mortal(newSVpv(rel,  0)));
    PUTBACK;

    int count = call_sv(cb, G_ARRAY|G_EVAL);
    SPAGAIN;

    if (SvTRUE(ERRSV)) {
        const char *err = SvPV_nolen(ERRSV);
        size_t len = strlen(err);
        char *b = jsonnet_realloc(ctx->vm, NULL, len);
        memcpy(b, err, len);
        *buf = b; *buflen = len;
        *found_here = NULL;
        FREETMPS; LEAVE;
        return 1;
    }

    if (count < 2) {
        const char *err = "import_callback must return (found_here, content) or (undef, error)";
        size_t len = strlen(err);
        char *b = jsonnet_realloc(ctx->vm, NULL, len);
        memcpy(b, err, len);
        *buf = b; *buflen = len;
        *found_here = NULL;
        FREETMPS; LEAVE;
        return 1;
    }

    SV *content_sv = POPs;
    SV *found_sv   = POPs;

    if (!SvOK(found_sv)) {
        /* failure */
        STRLEN elen;
        const char *emsg = SvPVbyte(content_sv, elen);
        char *b = jsonnet_realloc(ctx->vm, NULL, elen);
        memcpy(b, emsg, elen);
        *buf = b; *buflen = (size_t)elen;
        *found_here = NULL;
        ok = 0;
    } else {
        /* success */
        STRLEN flen, clen;
        const char *f = SvPVbyte(found_sv, flen);
        const char *c = SvPVbyte(content_sv, clen);

        char *fh = jsonnet_realloc(ctx->vm, NULL, flen + 1);
        memcpy(fh, f, flen);
        fh[flen] = '\0';

        char *b = jsonnet_realloc(ctx->vm, NULL, clen);
        memcpy(b, c, clen);

        *found_here = fh;
        *buf = b;
        *buflen = (size_t)clen;
        ok = 1;
    }

    PUTBACK;
    FREETMPS; LEAVE;
    return ok ? 0 : 1;
}

/* Convert Perl SV to JsonnetJsonValue recursively (primitives/array/hash). */
static struct JsonnetJsonValue*
perl_to_json(struct JsonnetVm *vm, PerlInterpreter *perl, SV *sv, int *success, SV **errsv)
{
    dTHXa(perl);  /* <- теперь всё Perl API в норме */
    if (!SvOK(sv)) {
        *success = 1;
        return jsonnet_json_make_null(vm);
    }

    if (SvROK(sv)) {
        SV *rv = SvRV(sv);

        if (SvTYPE(rv) == SVt_PVAV) {
            AV *av = (AV*)rv;
            struct JsonnetJsonValue *arr = jsonnet_json_make_array(vm);
            SSize_t n = av_len(av);
            for (SSize_t i=0; i<=n; i++) {
                SV **elem = av_fetch(av, i, 0);
                if (!elem) continue;
                int ok = 1;
                SV *esv = NULL;
                struct JsonnetJsonValue *v = perl_to_json(vm, perl, *elem, &ok, &esv);
                if (!ok) {
                    *success = 0;
                    *errsv = esv;
                    return jsonnet_json_make_string(vm, SvPV_nolen(esv));
                }
                jsonnet_json_array_append(vm, arr, v);
            }
            *success = 1;
            return arr;
        }

        if (SvTYPE(rv) == SVt_PVHV) {
            HV *hv = (HV*)rv;
            struct JsonnetJsonValue *obj = jsonnet_json_make_object(vm);

            hv_iterinit(hv);
            HE *he;
            while ((he = hv_iternext(hv))) {
                SV *ksv = hv_iterkeysv(he);
                SV *vsv = hv_iterval(hv, he);

                STRLEN klen;
                const char *k = SvPVbyte(ksv, klen);

                int ok = 1;
                SV *esv = NULL;
                struct JsonnetJsonValue *v = perl_to_json(vm, perl, vsv, &ok, &esv);
                if (!ok) {
                    *success = 0;
                    *errsv = esv;
                    return jsonnet_json_make_string(vm, SvPV_nolen(esv));
                }

                jsonnet_json_object_append(vm, obj, k, v);
            }

            *success = 1;
            return obj;
        }

        *success = 0;
        *errsv = newSVpv("Unsupported ref type returned from native callback", 0);
        return jsonnet_json_make_string(vm, SvPV_nolen(*errsv));
    }

    /* scalar */
    if ((SvNOK(sv) || SvIOK(sv)) && !SvPOK(sv)) {
        *success = 1;
        return jsonnet_json_make_number(vm, SvNV(sv));
    }

    /* treat as string */
    STRLEN slen;
    const char *s = SvPVutf8(sv, slen);
    *success = 1;
    return jsonnet_json_make_string(vm, s);
}

/* Native callback protocol:
   - args: only primitive Jsonnet types are supported as Perl scalars (string/number/bool/undef).
   - return: Perl scalar/arrayref/hashref => Jsonnet value; die/undef+errmsg => error.
*/
static struct JsonnetJsonValue*
perl_jsonnet_native_cb(void *vctx, const struct JsonnetJsonValue *const *argv, int *success)
{
    NativeCtx *ctx = (NativeCtx*)vctx;
#ifdef PERL_IMPLICIT_CONTEXT
    dTHXa(ctx->perl);
#else
    dTHX;
#endif
    dSP;

    ENTER; SAVETMPS;
    PUSHMARK(SP);

    for (int i=0; i<ctx->argc; i++) {
        const struct JsonnetJsonValue *a = argv[i];

        const char *str = jsonnet_json_extract_string(ctx->vm, a);
        if (str) {
            XPUSHs(sv_2mortal(newSVpv(str, 0)));
            continue;
        }

        double num;
        if (jsonnet_json_extract_number(ctx->vm, a, &num)) {
            XPUSHs(sv_2mortal(newSVnv(num)));
            continue;
        }

        int b = jsonnet_json_extract_bool(ctx->vm, a);
        if (b != 2) {
            XPUSHs(sv_2mortal(newSViv(b ? 1 : 0)));
            continue;
        }

        if (jsonnet_json_extract_null(ctx->vm, a)) {
            XPUSHs(&PL_sv_undef);
            continue;
        }

        /* complex value unsupported */
        XPUSHs(sv_2mortal(newSVpv("<<complex-jsonnet-value-unsupported>>", 0)));
    }

    PUTBACK;
    int count = call_sv(ctx->cb, G_SCALAR|G_EVAL);
    SPAGAIN;

    if (SvTRUE(ERRSV) || count < 1) {
        const char *err = SvTRUE(ERRSV) ? SvPV_nolen(ERRSV)
                                        : "native callback returned nothing";
        *success = 0;
        struct JsonnetJsonValue *ev = jsonnet_json_make_string(ctx->vm, err);
        FREETMPS; LEAVE;
        return ev;
    }

    SV *ret = POPs;

    int ok = 1;
    SV *esv = NULL;
    struct JsonnetJsonValue *v = perl_to_json(ctx->vm, ctx->perl, ret, &ok, &esv);
    if (!ok) {
        *success = 0;
        const char *err = esv ? SvPV_nolen(esv) : "native callback conversion error";
        v = jsonnet_json_make_string(ctx->vm, err);
    } else {
        *success = 1;
    }

    PUTBACK;
    FREETMPS; LEAVE;
    return v;
}

/* ---------- XS bindings ---------- */

MODULE = Jsonnet::XS    PACKAGE = Jsonnet::XS
PROTOTYPES: ENABLE

PerlJsonnetVm *
_new()
CODE:
    Newxz(RETVAL, 1, PerlJsonnetVm);
    RETVAL->vm = jsonnet_make();
    if (!RETVAL->vm) croak("jsonnet_make() returned NULL");
    RETVAL->import_ctx = NULL;
    RETVAL->native_head = NULL;
OUTPUT:
    RETVAL

void
DESTROY(PerlJsonnetVm *pvm)
CODE:
    if (!pvm) XSRETURN_EMPTY;
    free_import_ctx(pvm);
    free_native_ctxs(pvm);
    if (pvm->vm) jsonnet_destroy(pvm->vm);
    Safefree(pvm);

void
max_stack(PerlJsonnetVm *pvm, unsigned int v)
CODE:
    jsonnet_max_stack(pvm->vm, v);

void
gc_min_objects(PerlJsonnetVm *pvm, unsigned int v)
CODE:
    jsonnet_gc_min_objects(pvm->vm, v);

void
gc_growth_trigger(PerlJsonnetVm *pvm, double v)
CODE:
    jsonnet_gc_growth_trigger(pvm->vm, v);

void
max_trace(PerlJsonnetVm *pvm, unsigned int v)
CODE:
    jsonnet_max_trace(pvm->vm, v);

void
string_output(PerlJsonnetVm *pvm, int v)
CODE:
    jsonnet_string_output(pvm->vm, v);

void
jpath_add(PerlJsonnetVm *pvm, const char *path)
CODE:
    jsonnet_jpath_add(pvm->vm, path);

void
ext_var(PerlJsonnetVm *pvm, const char *key, const char *val)
CODE:
    jsonnet_ext_var(pvm->vm, key, val);

void
ext_code(PerlJsonnetVm *pvm, const char *key, const char *code)
CODE:
    jsonnet_ext_code(pvm->vm, key, code);

void
tla_var(PerlJsonnetVm *pvm, const char *key, const char *val)
CODE:
    jsonnet_tla_var(pvm->vm, key, val);

void
tla_code(PerlJsonnetVm *pvm, const char *key, const char *code)
CODE:
    jsonnet_tla_code(pvm->vm, key, code);

SV *
evaluate_file(PerlJsonnetVm *pvm, const char *filename)
PREINIT:
    int error = 0;
    char *out;
    SV *sv;
CODE:
    out = jsonnet_evaluate_file(pvm->vm, filename, &error);
    if (!out) croak("jsonnet_evaluate_file() returned NULL");
    sv = newSVpv(out, 0);
    jsonnet_realloc(pvm->vm, out, 0);
    if (error) croak("%s", SvPV_nolen(sv));
    RETVAL = sv;
OUTPUT:
    RETVAL

SV *
evaluate_snippet(PerlJsonnetVm *pvm, const char *filename, const char *snippet)
PREINIT:
    int error = 0;
    char *out;
    SV *sv;
CODE:
    out = jsonnet_evaluate_snippet(pvm->vm, filename, snippet, &error);
    if (!out) croak("jsonnet_evaluate_snippet() returned NULL");
    sv = newSVpv(out, 0);
    jsonnet_realloc(pvm->vm, out, 0);
    if (error) croak("%s", SvPV_nolen(sv));
    RETVAL = sv;
OUTPUT:
    RETVAL

SV *
evaluate_file_multi(PerlJsonnetVm *pvm, const char *filename)
PREINIT:
    int error = 0;
    char *out;
    HV *hv;
CODE:
    out = jsonnet_evaluate_file_multi(pvm->vm, filename, &error);
    if (!out) croak("jsonnet_evaluate_file_multi() returned NULL");

    if (error) {
        SV *esv = newSVpv(out, 0);
        jsonnet_realloc(pvm->vm, out, 0);
        croak("%s", SvPV_nolen(esv));
    }

    hv = newHV();
    char *p = out;
    while (*p) {
        char *fname = p; size_t fl = strlen(fname); p += fl + 1;
        char *json  = p; size_t jl = strlen(json ); p += jl + 1;
        hv_store(hv, fname, (I32)fl, newSVpv(json, jl), 0);
    }

    jsonnet_realloc(pvm->vm, out, 0);
    RETVAL = newRV_noinc((SV*)hv);
OUTPUT:
    RETVAL

SV *
evaluate_snippet_multi(PerlJsonnetVm *pvm, const char *filename, const char *snippet)
PREINIT:
    int error = 0;
    char *out;
    HV *hv;
CODE:
    out = jsonnet_evaluate_snippet_multi(pvm->vm, filename, snippet, &error);
    if (!out) croak("jsonnet_evaluate_snippet_multi() returned NULL");

    if (error) {
        SV *esv = newSVpv(out, 0);
        jsonnet_realloc(pvm->vm, out, 0);
        croak("%s", SvPV_nolen(esv));
    }

    hv = newHV();
    char *p = out;
    while (*p) {
        char *fname = p; size_t fl = strlen(fname); p += fl + 1;
        char *json  = p; size_t jl = strlen(json ); p += jl + 1;
        hv_store(hv, fname, (I32)fl, newSVpv(json, jl), 0);
    }

    jsonnet_realloc(pvm->vm, out, 0);
    RETVAL = newRV_noinc((SV*)hv);
OUTPUT:
    RETVAL

SV *
evaluate_file_stream(PerlJsonnetVm *pvm, const char *filename)
PREINIT:
    int error = 0;
    char *out;
    AV *av;
CODE:
    out = jsonnet_evaluate_file_stream(pvm->vm, filename, &error);
    if (!out) croak("jsonnet_evaluate_file_stream() returned NULL");

    if (error) {
        SV *esv = newSVpv(out, 0);
        jsonnet_realloc(pvm->vm, out, 0);
        croak("%s", SvPV_nolen(esv));
    }

    av = newAV();
    char *p = out;
    while (*p) {
        size_t l = strlen(p);
        av_push(av, newSVpv(p, l));
        p += l + 1;
    }

    jsonnet_realloc(pvm->vm, out, 0);
    RETVAL = newRV_noinc((SV*)av);
OUTPUT:
    RETVAL

SV *
evaluate_snippet_stream(PerlJsonnetVm *pvm, const char *filename, const char *snippet)
PREINIT:
    int error = 0;
    char *out;
    AV *av;
CODE:
    out = jsonnet_evaluate_snippet_stream(pvm->vm, filename, snippet, &error);
    if (!out) croak("jsonnet_evaluate_snippet_stream() returned NULL");

    if (error) {
        SV *esv = newSVpv(out, 0);
        jsonnet_realloc(pvm->vm, out, 0);
        croak("%s", SvPV_nolen(esv));
    }

    av = newAV();
    char *p = out;
    while (*p) {
        size_t l = strlen(p);
        av_push(av, newSVpv(p, l));
        p += l + 1;
    }

    jsonnet_realloc(pvm->vm, out, 0);
    RETVAL = newRV_noinc((SV*)av);
OUTPUT:
    RETVAL

void
import_callback(PerlJsonnetVm *pvm, SV *coderef)
CODE:
    if (!SvROK(coderef) || SvTYPE(SvRV(coderef)) != SVt_PVCV)
        croak("import_callback expects a coderef");

    free_import_ctx(pvm);

    Newxz(pvm->import_ctx, 1, PerlImportCtx);
    pvm->import_ctx->vm   = pvm->vm;
#ifdef PERL_IMPLICIT_CONTEXT
    pvm->import_ctx->perl = aTHX;
#else
    pvm->import_ctx->perl = NULL;
#endif
    pvm->import_ctx->cb   = SvREFCNT_inc(coderef);

    jsonnet_import_callback(pvm->vm, perl_jsonnet_import_cb, pvm->import_ctx);

void
native_callback(PerlJsonnetVm *pvm, const char *name, SV *coderef, SV *params_avref)
PREINIT:
    AV *params_av;
    SSize_t n;
    NativeCtx *ctx;
CODE:
    if (!SvROK(coderef) || SvTYPE(SvRV(coderef)) != SVt_PVCV)
        croak("native_callback expects a coderef");
    if (!SvROK(params_avref) || SvTYPE(SvRV(params_avref)) != SVt_PVAV)
        croak("native_callback expects params as arrayref");

    params_av = (AV*)SvRV(params_avref);
    n = av_len(params_av) + 1; /* count */

    Newxz(ctx, 1, NativeCtx);
    ctx->vm   = pvm->vm;
#ifdef PERL_IMPLICIT_CONTEXT
    ctx->perl = aTHX;
#else
    ctx->perl = NULL;
#endif
    ctx->cb   = SvREFCNT_inc(coderef);
    ctx->argc = (int)n;

    /* build stable NULL-terminated params array */
    Newxz(ctx->params, (int)n + 1, char*);
    for (int i=0; i<(int)n; i++) {
        SV **psv = av_fetch(params_av, i, 0);
        if (!psv || !SvOK(*psv))
            croak("params[%d] is undefined", i);

        STRLEN l;
        const char *p = SvPVutf8(*psv, l);
        ctx->params[i] = savepvn(p, l);
    }
    ctx->params[n] = NULL;

    jsonnet_native_callback(pvm->vm, name, perl_jsonnet_native_cb, ctx,
                            (const char *const*)ctx->params);

    /* chain for later free */
    ctx->next = pvm->native_head;
    pvm->native_head = ctx;
