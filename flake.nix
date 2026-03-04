{
  description = "DataFusion Comet — dev shell con Spark 3.5.7 + build tools";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        sparkVersion = "3.5.7";
        sparkVersionShort = "3.5";
        hadoopProfile = "3";
        scalaVersion = "2.12";
        sparkDirName = "spark-${sparkVersion}-bin-hadoop${hadoopProfile}";
        sparkTgz = "${sparkDirName}.tgz";

        # URL oficial de Apache Spark
        sparkUrl = "https://archive.apache.org/dist/spark/spark-${sparkVersion}/${sparkTgz}";

        # Script para descargar Spark si no existe
        downloadSpark = pkgs.writeShellScriptBin "comet-setup" ''
          SPARK_LOCAL="$PWD/.spark/${sparkDirName}"
          if [ ! -d "$SPARK_LOCAL" ]; then
            echo "Descargando Spark ${sparkVersion}..."
            mkdir -p .spark
            ${pkgs.curl}/bin/curl -fSL "${sparkUrl}" -o ".spark/${sparkTgz}"
            tar xzf ".spark/${sparkTgz}" -C .spark/
            rm -f ".spark/${sparkTgz}"
            echo "Spark ${sparkVersion} instalado en .spark/"
          else
            echo "Spark ${sparkVersion} ya existe en .spark/"
          fi
          echo ""
          echo "SPARK_HOME=$SPARK_LOCAL"
        '';

        # Script para compilar Comet (usa make release = cargo build --release + mvnw install -Prelease)
        cometBuild = pkgs.writeShellScriptBin "comet-build" ''
          set -e
          echo "=== Building Comet (native + JVM) via make release ==="
          echo "    cargo build --release + mvnw install -Prelease -DskipTests"
          echo ""
          make release PROFILES="-Drat.skip=true"
          echo ""
          COMET_JAR=$(ls spark/target/comet-spark-spark${sparkVersionShort}_${scalaVersion}-*.jar 2>/dev/null | grep -v -E '(sources|javadoc|tests)' | head -1)
          echo "JAR ready: $COMET_JAR"
        '';

        # Script para build rapido solo Rust (debug, sin JAR)
        cometBuildDebug = pkgs.writeShellScriptBin "comet-build-debug" ''
          set -e
          echo "=== Building native only (debug) ==="
          cd native && cargo build
          echo "Done. Note: run 'comet-build' for a full release build with JAR."
        '';

        # Script para lanzar spark-shell con Comet + Spark UI
        cometShell = pkgs.writeShellScriptBin "comet-shell" ''
          SPARK_LOCAL="$PWD/.spark/${sparkDirName}"
          if [ ! -d "$SPARK_LOCAL" ]; then
            echo "Spark no encontrado. Ejecuta 'comet-setup' primero."
            exit 1
          fi
          export SPARK_HOME="$SPARK_LOCAL"

          COMET_JAR=$(ls spark/target/comet-spark-spark*.jar 2>/dev/null | grep -v -E '(sources|javadoc|tests)' | head -1)
          if [ -z "$COMET_JAR" ]; then
            echo "JAR de Comet no encontrado. Ejecuta 'comet-build' primero."
            exit 1
          fi

          echo "Lanzando spark-shell con Comet..."
          echo "  SPARK_HOME=$SPARK_HOME"
          echo "  COMET_JAR=$COMET_JAR"
          echo "  Spark UI: http://localhost:4040"
          echo ""

          exec "$SPARK_HOME/bin/spark-shell" \
            --master "local[4]" \
            --jars "$COMET_JAR" \
            --driver-class-path "$COMET_JAR" \
            --conf spark.executor.extraClassPath="$COMET_JAR" \
            --conf spark.plugins=org.apache.spark.CometPlugin \
            --conf spark.shuffle.manager=org.apache.spark.sql.comet.execution.shuffle.CometShuffleManager \
            --conf spark.comet.enabled=true \
            --conf spark.comet.exec.enabled=true \
            --conf spark.comet.exec.shuffle.enabled=true \
            --conf spark.comet.explainFallback.enabled=true \
            --conf spark.memory.offHeap.enabled=true \
            --conf spark.memory.offHeap.size=4g \
            "$@"
        '';

        # Script para lanzar spark-sql con Comet
        cometSql = pkgs.writeShellScriptBin "comet-sql" ''
          SPARK_LOCAL="$PWD/.spark/${sparkDirName}"
          if [ ! -d "$SPARK_LOCAL" ]; then
            echo "Spark no encontrado. Ejecuta 'comet-setup' primero."
            exit 1
          fi
          export SPARK_HOME="$SPARK_LOCAL"

          COMET_JAR=$(ls spark/target/comet-spark-spark*.jar 2>/dev/null | grep -v -E '(sources|javadoc|tests)' | head -1)
          if [ -z "$COMET_JAR" ]; then
            echo "JAR de Comet no encontrado. Ejecuta 'comet-build' primero."
            exit 1
          fi

          echo "Lanzando spark-sql con Comet..."
          echo "  Spark UI: http://localhost:4040"
          echo ""

          exec "$SPARK_HOME/bin/spark-sql" \
            --master "local[4]" \
            --jars "$COMET_JAR" \
            --driver-class-path "$COMET_JAR" \
            --conf spark.executor.extraClassPath="$COMET_JAR" \
            --conf spark.plugins=org.apache.spark.CometPlugin \
            --conf spark.shuffle.manager=org.apache.spark.sql.comet.execution.shuffle.CometShuffleManager \
            --conf spark.comet.enabled=true \
            --conf spark.comet.exec.enabled=true \
            --conf spark.comet.exec.shuffle.enabled=true \
            --conf spark.comet.explainFallback.enabled=true \
            --conf spark.memory.offHeap.enabled=true \
            --conf spark.memory.offHeap.size=4g \
            "$@"
        '';

        # Script para pyspark con Comet
        cometPyspark = pkgs.writeShellScriptBin "comet-pyspark" ''
          SPARK_LOCAL="$PWD/.spark/${sparkDirName}"
          if [ ! -d "$SPARK_LOCAL" ]; then
            echo "Spark not found. Run 'comet-setup' first."
            exit 1
          fi
          export SPARK_HOME="$SPARK_LOCAL"

          COMET_JAR=$(ls spark/target/comet-spark-spark*.jar 2>/dev/null | grep -v -E '(sources|javadoc|tests)' | head -1)
          if [ -z "$COMET_JAR" ]; then
            echo "Comet JAR not found. Run 'comet-build' first."
            exit 1
          fi

          echo "Launching pyspark with Comet..."
          echo "  Spark UI: http://localhost:4040"
          echo ""

          exec "$SPARK_HOME/bin/pyspark" \
            --master "local[4]" \
            --jars "$COMET_JAR" \
            --driver-class-path "$COMET_JAR" \
            --conf spark.executor.extraClassPath="$COMET_JAR" \
            --conf spark.plugins=org.apache.spark.CometPlugin \
            --conf spark.shuffle.manager=org.apache.spark.sql.comet.execution.shuffle.CometShuffleManager \
            --conf spark.comet.enabled=true \
            --conf spark.comet.exec.enabled=true \
            --conf spark.comet.exec.shuffle.enabled=true \
            --conf spark.comet.explainFallback.enabled=true \
            --conf spark.memory.offHeap.enabled=true \
            --conf spark.memory.offHeap.size=4g \
            "$@"
        '';

        # Script para spark-submit con Comet
        cometSubmit = pkgs.writeShellScriptBin "comet-submit" ''
          SPARK_LOCAL="$PWD/.spark/${sparkDirName}"
          if [ ! -d "$SPARK_LOCAL" ]; then
            echo "Spark no encontrado. Ejecuta 'comet-setup' primero."
            exit 1
          fi
          export SPARK_HOME="$SPARK_LOCAL"

          COMET_JAR=$(ls spark/target/comet-spark-spark*.jar 2>/dev/null | grep -v -E '(sources|javadoc|tests)' | head -1)
          if [ -z "$COMET_JAR" ]; then
            echo "JAR de Comet no encontrado. Ejecuta 'comet-build' primero."
            exit 1
          fi

          echo "Lanzando spark-submit con Comet..."
          echo "  Spark UI: http://localhost:4040"
          echo ""

          exec "$SPARK_HOME/bin/spark-submit" \
            --master "local[4]" \
            --jars "$COMET_JAR" \
            --driver-class-path "$COMET_JAR" \
            --conf spark.executor.extraClassPath="$COMET_JAR" \
            --conf spark.plugins=org.apache.spark.CometPlugin \
            --conf spark.shuffle.manager=org.apache.spark.sql.comet.execution.shuffle.CometShuffleManager \
            --conf spark.comet.enabled=true \
            --conf spark.comet.exec.enabled=true \
            --conf spark.comet.exec.shuffle.enabled=true \
            --conf spark.comet.exec.shuffle.mode=native \
            --conf spark.comet.explainFallback.enabled=true \
            --conf spark.memory.offHeap.enabled=true \
            --conf spark.memory.offHeap.size=4g \
            "$@"
        '';

      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # JVM (Spark / Maven)
            jdk17
            maven

            # Rust (native DataFusion engine)
            rustup
            protobuf

            # C/C++ (needed by bindgen, jni, hdfs-sys)
            clang
            llvmPackages.libclang

            # System libs
            openssl
            openssl.dev

            # Build tools
            cmake
            pkg-config
            curl
            git

            # Comet helper scripts
            downloadSpark
            cometBuild
            cometBuildDebug
            cometShell
            cometSql
            cometPyspark
            cometSubmit
          ];

          shellHook = ''
            export JAVA_HOME="${pkgs.jdk17.home}"

            # bindgen needs libclang
            export LIBCLANG_PATH="${pkgs.llvmPackages.libclang.lib}/lib"

            # openssl-sys
            export OPENSSL_DIR="${pkgs.openssl.dev}"
            export OPENSSL_LIB_DIR="${pkgs.openssl.out}/lib"
            export OPENSSL_INCLUDE_DIR="${pkgs.openssl.dev}/include"

            # Si Spark ya esta descargado, exportar SPARK_HOME
            if [ -d "$PWD/.spark/${sparkDirName}" ]; then
              export SPARK_HOME="$PWD/.spark/${sparkDirName}"
            fi

            echo "╔══════════════════════════════════════════════╗"
            echo "║   datafusion-comet dev shell                 ║"
            echo "╚══════════════════════════════════════════════╝"
            echo ""
            echo "  Java:     $(java -version 2>&1 | head -1)"
            echo "  Maven:    $(mvn --version 2>&1 | head -1)"
            echo "  Protoc:   $(protoc --version)"
            if [ -n "$SPARK_HOME" ]; then
              echo "  Spark:    $("$SPARK_HOME/bin/spark-shell" --version 2>&1 | grep -oP 'version \K[\d.]+' | head -1 || echo "${sparkVersion}")"
            else
              echo "  Spark:    (not installed — run 'comet-setup')"
            fi
            echo ""
            echo "Quick start:"
            echo "  1. comet-setup       — download Spark ${sparkVersion} (first time only)"
            echo "  2. comet-build       — full release build (native + JVM)"
            echo "  3. comet-shell       — spark-shell with Comet (UI at localhost:4040)"
            echo "  4. comet-sql         — spark-sql with Comet"
            echo "  5. comet-pyspark     — pyspark with Comet"
            echo "  6. comet-submit      — spark-submit with Comet"
            echo ""
            echo "Other:"
            echo "  comet-build-debug    — quick Rust-only debug build (no JAR)"
            echo "  make release         — same as comet-build"
            echo "  make test            — run all tests (Rust + JVM)"

            # Prompt limpio: proyecto + cometa + directorio
            export PS1='\[\033[1;36m\]datafusion-comet\[\033[0m\] ☄️  \[\033[1;33m\]\W\[\033[0m\] \$ '
          '';
        };
      });
}
