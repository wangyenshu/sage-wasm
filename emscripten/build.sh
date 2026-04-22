#!/usr/bin/env bash
set -eux

BASEDIR="$(pwd)"

if ! command -v emmake &> /dev/null; then
    echo "Error: Please install and source Emscripten 3.1.23."
    echo "See https://emscripten.org/docs/getting_started/downloads.html"
    exit 1
fi

AUX_BUILD="$BASEDIR/emscripten/build"
AUX_PREFIX="$BASEDIR/emscripten/install"
EXTERN_DIR="$BASEDIR/emscripten/extern"

mkdir -p "$AUX_BUILD"
mkdir -p "$AUX_PREFIX"
mkdir -p "$EXTERN_DIR"

# Generate autotools scripts if missing
if [[ ! -f ./configure ]]; then
    echo "Bootstrapping SageMath configure script..."
    make configure
fi

# EXTERNAL LIBRARIES

# --- GMP ---
(
    mkdir -p "$AUX_BUILD/gmp"
    cd "$AUX_BUILD/gmp"
    if [[ ! -d "$EXTERN_DIR/gmp" ]]; then
        echo "Downloading GMP source..."
        hg clone https://gmplib.org/repo/gmp/ "$EXTERN_DIR/gmp"
        cd "$EXTERN_DIR/gmp" && ./.bootstrap && cd -
    fi
    if [[ ! -f config.status ]]; then
        CC_FOR_BUILD=/usr/bin/gcc ABI=standard \
        emconfigure "$EXTERN_DIR/gmp/configure" \
            --build i686-pc-linux-gnu --host none \
            --disable-assembly --enable-cxx \
            --prefix="$AUX_PREFIX"
    fi
    emmake make -j8
    emmake make install
)

# --- MPFR ---
(
    mkdir -p "$AUX_BUILD/mpfr"
    cd "$AUX_BUILD/mpfr"
    if [[ ! -d "$EXTERN_DIR/mpfr" ]]; then
        echo "Downloading MPFR source..."
        git clone https://gitlab.inria.fr/mpfr/mpfr.git "$EXTERN_DIR/mpfr"
        cd "$EXTERN_DIR/mpfr" && ./autogen.sh && cd -
    fi
    if [[ ! -f config.status ]]; then
        emconfigure "$EXTERN_DIR/mpfr/configure" \
            --build i686-pc-linux-gnu --host none \
            --with-gmp="$AUX_PREFIX" \
            --disable-shared \
            --prefix="$AUX_PREFIX"
    fi
    emmake make -j8
    emmake make install
)

# --- FLINT ---
(
    mkdir -p "$AUX_BUILD/flint"
    cd "$AUX_BUILD/flint"
    if [[ ! -d "$EXTERN_DIR/flint2" ]]; then
        echo "Cloning Flint..."
        git clone --depth 1 https://github.com/wbhart/flint2.git "$EXTERN_DIR/flint2"
        cd "$EXTERN_DIR/flint2" && ./bootstrap.sh && cd -
    fi
    if [[ ! -f Makefile ]]; then
        emconfigure "$EXTERN_DIR/flint2/configure" \
            --build=i686-pc-linux-gnu \
            --host=wasm32-unknown-emscripten \
            --with-gmp="$AUX_PREFIX" \
            --with-mpfr="$AUX_PREFIX" \
            --disable-shared \
            --disable-assembly \
            --prefix="$AUX_PREFIX"
    fi
    emmake make -j8
    emmake make install
)

# --- NTL ---
(
    mkdir -p "$AUX_BUILD/ntl"
    cd "$AUX_BUILD/ntl"
    
    if [[ ! -d "$EXTERN_DIR/ntl" ]]; then
        echo "Cloning NTL..."
        git clone https://github.com/libntl/ntl.git "$EXTERN_DIR/ntl"
    fi
    cd "$EXTERN_DIR/ntl/src"
    
    if [[ ! -f makefile ]]; then
        emconfigure ./configure \
            CXX="em++" \
            CXXFLAGS="-O2 -fexceptions -s WASM=1 -s NODERAWFS=1" \
            PREFIX="$AUX_PREFIX" \
            GMP_PREFIX="$AUX_PREFIX" \
            NTL_GMP_LIP=on \
            NTL_STD_CXX14=on \
            SHARED=off \
            NATIVE=off \
            TUNE=generic \
            NTL_THREADS=off

        sed -e 's/^CC=gcc/CC=emcc -s NODERAWFS=1/' \
            -e 's/^WIZARD=on/WIZARD=off/' \
            makefile > makefile.patched
        mv makefile.patched makefile
    fi
    
    if ! emmake make -j8; then
        
        sed -e 's|^\t\./MakeDesc|\tchmod +x ./MakeDesc \&\& node ./MakeDesc|' \
            -e 's|^\t\./gen_gmp_aux|\tchmod +x ./gen_gmp_aux \&\& node ./gen_gmp_aux|' \
            -e 's|^\t\./gen_lip_gmp_aux|\tchmod +x ./gen_lip_gmp_aux \&\& node ./gen_lip_gmp_aux|' \
            -e 's|^\t\./gen_lip_gmp_aux|\tchmod +x ./gen_lip_gmp_aux \&\& node ./gen_lip_gmp_aux|' \
            makefile > makefile.patched
        mv makefile.patched makefile
        
        sed -i 's|if ./CheckFeatures|if node ./CheckFeatures|g' MakeCheckFeatures
        
        if [ -f MakeCheckThreads ]; then
            sed -i 's|./CheckThreads|node ./CheckThreads|g' MakeCheckThreads
        fi
        
        emmake make -j8
    fi

    emmake make install
    emranlib "$AUX_PREFIX/lib/libntl.a"
)

# --- CDDLIB ---
(
    if [[ ! -d "$EXTERN_DIR/cddlib" ]]; then
        echo "Cloning cddlib..."
        git clone https://github.com/cddlib/cddlib.git "$EXTERN_DIR/cddlib"
    fi

    cd "$EXTERN_DIR/cddlib"
    
    if [[ ! -f configure ]]; then
        ./bootstrap
    fi

    if [[ ! -f Makefile ]]; then
        CPPFLAGS="-I$AUX_PREFIX/include" \
        LDFLAGS="-L$AUX_PREFIX/lib" \
        CFLAGS="-O2" \
        CXXFLAGS="-O2" \
        emconfigure ./configure \
            --with-gmp="$AUX_PREFIX" \
            --disable-shared \
            --prefix="$AUX_PREFIX"
    fi
    
    emmake make -j8
    emmake make install

    cd "$AUX_PREFIX/include"
    ln -sf cddlib/*.h .
    ln -sf cddmp.h cdd_mp.h
)

# --- LIBATOMIC_OPS ---
# --- LIBBOOST ---
# --- LIBBRAIDING ---
# --- LIBBRIAL ---
# --- LIBBZ2 ---
# --- LIBCLIQUER ---
# --- LIBCURL ---
# --- LIBECL ---
# --- LIBECM ---
# --- LIBFFI ---
# --- LIBFFLAS_FFPACK ---
# --- LIBFPLLL ---
# --- LIBFREETYPE ---
# --- LIBGAP ---
# --- LIBGC (Boehm GC) ---
# --- LIBGD ---
# --- LIBGF2X ---
# --- LIBGFAN ---
# --- LIBGIVARO ---
# --- LIBGLPK ---
# --- LIBGSL ---
# --- LIBHOMFLY ---
# --- LIBIML ---
# --- LIBLFUNCTION ---
# --- LIBLINBOX ---
# --- LIBLRCALC ---
# --- LIBLZMA ---
# --- LIBM4RI ---
# --- LIBM4RIE ---
# --- LIBMPC ---
# --- LIBMPFI ---
# --- LIBNAUTY ---
# --- LIBNCURSES ---
# --- LIBOPENBLAS ---
# --- LIBOPENSSL ---
# --- LIBPARI ---
# --- LIBPLANARITY ---
# --- LIBPPL ---
# --- LIBPRIMECOUNT ---
# --- LIBPRIMESIEVE ---
# --- LIBPYTHON3 ---
# --- LIBQHULL ---
# --- LIBREADLINE ---
# --- LIBRW ---
# --- LIBSINGULAR ---
# --- LIBSQLITE3 ---
# --- LIBSUITESPARSE ---
# --- LIBSYMMETRICA ---
# --- LIBZ ---
# --- LIBZMQ ---

# ==========================================

export EMCC_CFLAGS="-fexceptions"

export CFLAGS="-O2 -fexceptions -s WASM=1 -I$AUX_PREFIX/include"
export CXXFLAGS="-O2 -fexceptions -s WASM=1 -std=c++14 -I$AUX_PREFIX/include"
export LDFLAGS="-L$AUX_PREFIX/lib -fexceptions -s ASYNCIFY=1 -s ALLOW_MEMORY_GROWTH=1 -s ERROR_ON_UNDEFINED_SYMBOLS=1"

echo "Configuring SageMath for wasm32-unknown-emscripten..."
emconfigure ./configure \
    --build=i686-pc-linux-gnu \
    --host=wasm32-unknown-emscripten \
    --prefix="$AUX_PREFIX" \
    --disable-shared \
    --enable-static \
    --without-system-python3 \
    --enable-gmp \
    --enable-mpfr \
    --enable-flint \
    --enable-gsl \
    CC="emcc -fexceptions" \
    CXX="em++ -fexceptions" \
    AR="emar" \
    RANLIB="emranlib"

echo "Building SageMath modules..."
emmake make -j8

echo "SageMath Wasm build complete."