{ stdenv, fetchurl }:
  let
    mkJenkinsPlugin = { name, src }:
      stdenv.mkDerivation {
        inherit name src;
        phases = "installPhase";
        installPhase = "cp \$src \$out";
        };
  in {
    antisamy-markup-formatter = mkJenkinsPlugin {
      name = "antisamy-markup-formatter";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/antisamy-markup-formatter/162.v0e6ec0fcfcf6/antisamy-markup-formatter.hpi";
        sha256 = "3d4144a78b14ccc4a8f370ccea82c93bd56fadd900b2db4ebf7f77ce2979efd6";
        };
      };
    apache-httpcomponents-client-4-api = mkJenkinsPlugin {
      name = "apache-httpcomponents-client-4-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/apache-httpcomponents-client-4-api/4.5.14-208.v438351942757/apache-httpcomponents-client-4-api.hpi";
        sha256 = "9ed0ccda20a0ea11e2ba5be299f03b30692dd5a2f9fdc7853714507fda8acd0f";
        };
      };
    apache-httpcomponents-client-5-api = mkJenkinsPlugin {
      name = "apache-httpcomponents-client-5-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/apache-httpcomponents-client-5-api/5.3.1-1.0/apache-httpcomponents-client-5-api.hpi";
        sha256 = "021d4e141bb23594ef01c1b7dddce120f5f99315a3fd302786db472dcb61d3bd";
        };
      };
    asm-api = mkJenkinsPlugin {
      name = "asm-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/asm-api/9.7-33.v4d23ef79fcc8/asm-api.hpi";
        sha256 = "cb92a55ed601e06b00335db082f6df392a2b440b6bb88da8d3d5ccc67c87749f";
        };
      };
    authentication-tokens = mkJenkinsPlugin {
      name = "authentication-tokens";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/authentication-tokens/1.53.v1c90fd9191a_b_/authentication-tokens.hpi";
        sha256 = "55086066466a2b66fa855bc2a754a376964b7c7ce258f5c4b73c264e072c3bdc";
        };
      };
    bootstrap5-api = mkJenkinsPlugin {
      name = "bootstrap5-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/bootstrap5-api/5.3.3-1/bootstrap5-api.hpi";
        sha256 = "e0d0f7c92dae2f7977c28ceb6a5b2562b7012d1704888bff3bc176abda0cb269";
        };
      };
    bouncycastle-api = mkJenkinsPlugin {
      name = "bouncycastle-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/bouncycastle-api/2.30.1.77-225.v26ea_c9455fd9/bouncycastle-api.hpi";
        sha256 = "6b05cf59fde49c687300c8935d34a38c697656ca106c52ef33ab094643c211d8";
        };
      };
    branch-api = mkJenkinsPlugin {
      name = "branch-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/branch-api/2.1163.va_f1064e4a_a_f3/branch-api.hpi";
        sha256 = "07eb630439025688e49222d344b6f784ac464c24e600973a0d1fd7f467e3afe1";
        };
      };
    caffeine-api = mkJenkinsPlugin {
      name = "caffeine-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/caffeine-api/3.1.8-133.v17b_1ff2e0599/caffeine-api.hpi";
        sha256 = "a6c614655bc507345bf16b5c4615bb09b1a20f934c9bf0b15c02ccea4a5c0400";
        };
      };
    checks-api = mkJenkinsPlugin {
      name = "checks-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/checks-api/2.2.0/checks-api.hpi";
        sha256 = "b3df53ead1b0818b8c1f78912c695399e452f03206d0c771608aaf6b7edc2134";
        };
      };
    cloud-stats = mkJenkinsPlugin {
      name = "cloud-stats";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/cloud-stats/336.v788e4055508b_/cloud-stats.hpi";
        sha256 = "66831ae6f336e10c983be64e7f40704cc4a91da7f8c3b1606a8dcad110f3ec2c";
        };
      };
    cloudbees-folder = mkJenkinsPlugin {
      name = "cloudbees-folder";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/cloudbees-folder/6.928.v7c780211d66e/cloudbees-folder.hpi";
        sha256 = "92b4adb1748453026d9abefdd2820817069de84928c073c666de07a5a619cecb";
        };
      };
    command-launcher = mkJenkinsPlugin {
      name = "command-launcher";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/command-launcher/107.v773860566e2e/command-launcher.hpi";
        sha256 = "72e0ae8c9a31ac7f5a3906f7cacd34de26bdca3767bfef87027723850a68ca19";
        };
      };
    commons-lang3-api = mkJenkinsPlugin {
      name = "commons-lang3-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/commons-lang3-api/3.13.0-62.v7d18e55f51e2/commons-lang3-api.hpi";
        sha256 = "e27bbec4d37f26e7da0d0732b241ad0eb2b60826c3f7521808b1442727f54858";
        };
      };
    commons-text-api = mkJenkinsPlugin {
      name = "commons-text-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/commons-text-api/1.11.0-109.vfe16c66636eb_/commons-text-api.hpi";
        sha256 = "349f7a23fbbea314d0ecadac5ccc4aecd1df798a0dae43d370b3eb3fdcf2c931";
        };
      };
    conditional-buildstep = mkJenkinsPlugin {
      name = "conditional-buildstep";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/conditional-buildstep/1.4.3/conditional-buildstep.hpi";
        sha256 = "d2ce40b86abc42372085ace0a6bb3785d14ae27f0824709dfc2a2b3891a9e8a8";
        };
      };
    config-file-provider = mkJenkinsPlugin {
      name = "config-file-provider";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/config-file-provider/973.vb_a_80ecb_9a_4d0/config-file-provider.hpi";
        sha256 = "2dca5114092391a57709952e7d94a4e798eec6560e75c7c6ee17cd28f1b675ff";
        };
      };
    configuration-as-code = mkJenkinsPlugin {
      name = "configuration-as-code";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/configuration-as-code/1775.v810dc950b_514/configuration-as-code.hpi";
        sha256 = "6c4c864149a7cbca04b402bcdf3b37b0a6501226bffb0d362afd3c774c38de02";
        };
      };
    credentials = mkJenkinsPlugin {
      name = "credentials";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/credentials/1337.v60b_d7b_c7b_c9f/credentials.hpi";
        sha256 = "42ac1d8870c86fc60f3d6f8220ed37bdbc7f62b4a7874871db3ec662572825de";
        };
      };
    credentials-binding = mkJenkinsPlugin {
      name = "credentials-binding";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/credentials-binding/657.v2b_19db_7d6e6d/credentials-binding.hpi";
        sha256 = "6e905b964be1c0c0e6591c200d030447d170ec5c2eb5e88bac209e41c1847853";
        };
      };
    dashboard-view = mkJenkinsPlugin {
      name = "dashboard-view";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/dashboard-view/2.508.va_74654f026d1/dashboard-view.hpi";
        sha256 = "cd9fa18f9799b6026857bb308593eebcb846f65e8ac9a26441e07f0a3d7fdb34";
        };
      };
    display-url-api = mkJenkinsPlugin {
      name = "display-url-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/display-url-api/2.200.vb_9327d658781/display-url-api.hpi";
        sha256 = "2c43127027b16518293b94fa3f1792b7bd3db7234380c6a5249275d480fcbd04";
        };
      };
    docker-commons = mkJenkinsPlugin {
      name = "docker-commons";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/docker-commons/439.va_3cb_0a_6a_fb_29/docker-commons.hpi";
        sha256 = "70011c3a25f8df597d4bd7b02236d8fe6114041aad214109508886aefc6ac029";
        };
      };
    docker-java-api = mkJenkinsPlugin {
      name = "docker-java-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/docker-java-api/3.3.4-86.v39b_a_5ede342c/docker-java-api.hpi";
        sha256 = "ac3e4c5b6df8dd3b101463b374d422c8358c7a2bc28669be512de822efeb9015";
        };
      };
    docker-plugin = mkJenkinsPlugin {
      name = "docker-plugin";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/docker-plugin/1.6/docker-plugin.hpi";
        sha256 = "ca2758eb96f77b47c44be96d6de3f23ab75e908975514501baac56b4bd9bf345";
        };
      };
    durable-task = mkJenkinsPlugin {
      name = "durable-task";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/durable-task/555.v6802fe0f0b_82/durable-task.hpi";
        sha256 = "307cfaccba10295d9f7624abfc634026b9f6e2b83681804e6dd2b403a3df636e";
        };
      };
    echarts-api = mkJenkinsPlugin {
      name = "echarts-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/echarts-api/5.5.0-1/echarts-api.hpi";
        sha256 = "2e5eeb6c9fb836f5f6964024e54f7d241e43c9384f923a919baccff6ffd6b721";
        };
      };
    font-awesome-api = mkJenkinsPlugin {
      name = "font-awesome-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/font-awesome-api/6.5.2-1/font-awesome-api.hpi";
        sha256 = "5e77b7c6f5cd0423355c210cdd09389b62f10ac9fc0225d00bfd823efd30799f";
        };
      };
    git = mkJenkinsPlugin {
      name = "git";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/git/5.2.1/git.hpi";
        sha256 = "d4779c1925e2d82668e62d3a2bc948d0214e86acd4779d045727d84cb9d53e59";
        };
      };
    git-client = mkJenkinsPlugin {
      name = "git-client";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/git-client/4.7.0/git-client.hpi";
        sha256 = "c01ca53183d1ed70d2bb98b2df6145a82be6561aa83c591ff67b23d3044e655c";
        };
      };
    gitea = mkJenkinsPlugin {
      name = "gitea";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/gitea/1.4.7/gitea.hpi";
        sha256 = "ecbe7817cf0b548307aab2381501c5843bee82d64f0c49de4360d97a3bbc750f";
        };
      };
    gson-api = mkJenkinsPlugin {
      name = "gson-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/gson-api/2.10.1-15.v0d99f670e0a_7/gson-api.hpi";
        sha256 = "fa9d125a48224f3add5abb1148269a2ff843c17c43680f994c118f84bf237e3a";
        };
      };
    handy-uri-templates-2-api = mkJenkinsPlugin {
      name = "handy-uri-templates-2-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/handy-uri-templates-2-api/2.1.8-30.v7e777411b_148/handy-uri-templates-2-api.hpi";
        sha256 = "d635f86d7bf90cfae400f589e61ed9decf354fb28aab8d9ba8552446a1c913f4";
        };
      };
    instance-identity = mkJenkinsPlugin {
      name = "instance-identity";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/instance-identity/185.v303dc7c645f9/instance-identity.hpi";
        sha256 = "dc78c0a23fd3d16a769a78c7822a94862dc7ef37bbebb09cbea3fa06dc67fc6a";
        };
      };
    ionicons-api = mkJenkinsPlugin {
      name = "ionicons-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/ionicons-api/70.v2959a_b_74e3cf/ionicons-api.hpi";
        sha256 = "789a30ced3c70fdf6dee9535607433e85eda8facc7a3edc00d8c035068cb1fdd";
        };
      };
    jackson2-api = mkJenkinsPlugin {
      name = "jackson2-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/jackson2-api/2.17.0-379.v02de8ec9f64c/jackson2-api.hpi";
        sha256 = "5e2d919724da0a47cd01bdb9f614c8fc90862c09ce506d9b2ca340252bad225e";
        };
      };
    jakarta-activation-api = mkJenkinsPlugin {
      name = "jakarta-activation-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/jakarta-activation-api/2.1.3-1/jakarta-activation-api.hpi";
        sha256 = "ddc3df5d8c39a2a208661d69277120b1113373b04d06e2250615be2a65404b83";
        };
      };
    jakarta-mail-api = mkJenkinsPlugin {
      name = "jakarta-mail-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/jakarta-mail-api/2.1.3-1/jakarta-mail-api.hpi";
        sha256 = "851ab22ff0647f4d82baab4e526c6d0ddb3e64ad4969c516116b374ef778e539";
        };
      };
    javadoc = mkJenkinsPlugin {
      name = "javadoc";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/javadoc/243.vb_b_503b_b_45537/javadoc.hpi";
        sha256 = "0dfffce64e478edcdbbfde2df5913be2ff46e5e033daff8bc9bb616ca7528999";
        };
      };
    javax-activation-api = mkJenkinsPlugin {
      name = "javax-activation-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/javax-activation-api/1.2.0-6/javax-activation-api.hpi";
        sha256 = "8af800837a3bddca75d7f962fbcf535d1c3c214f323fa57c141cecdde61516a9";
        };
      };
    jaxb = mkJenkinsPlugin {
      name = "jaxb";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/jaxb/2.3.9-1/jaxb.hpi";
        sha256 = "8c9f7f98d996ade98b7a5dd0cd9d0aba661acea1b99a33f75778bacf39a64659";
        };
      };
    jjwt-api = mkJenkinsPlugin {
      name = "jjwt-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/jjwt-api/0.11.5-112.ve82dfb_224b_a_d/jjwt-api.hpi";
        sha256 = "339161525489ce8ab23d252b9399eda3b849a22faa3542be5ae7c559f9936e47";
        };
      };
    job-dsl = mkJenkinsPlugin {
      name = "job-dsl";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/job-dsl/1.87/job-dsl.hpi";
        sha256 = "3de24254966ba99d5184c9dc9fdf553271c8e7400446a6be2ce0117e7928b124";
        };
      };
    joda-time-api = mkJenkinsPlugin {
      name = "joda-time-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/joda-time-api/2.12.7-29.v5a_b_e3a_82269a_/joda-time-api.hpi";
        sha256 = "1d7e8164fee2e8b94e5ac5cf8522b5ab1a3a4ce254591c6c6445227427720697";
        };
      };
    jquery3-api = mkJenkinsPlugin {
      name = "jquery3-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/jquery3-api/3.7.1-2/jquery3-api.hpi";
        sha256 = "322d01e14a368e3131ff388dbc6fe062abaa6cb0a2bb761bc46516f1f7ca1066";
        };
      };
    jsch = mkJenkinsPlugin {
      name = "jsch";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/jsch/0.2.16-86.v42e010d9484b_/jsch.hpi";
        sha256 = "f0eb7f7ebaf374f7040e60a56ccd8af6fe471e883957df3a4fff116dda02dc12";
        };
      };
    json-api = mkJenkinsPlugin {
      name = "json-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/json-api/20240303-41.v94e11e6de726/json-api.hpi";
        sha256 = "d43ff9708ae0354ed6fe4c174acf4e00bd404d3c93251852203273518ff935a6";
        };
      };
    json-path-api = mkJenkinsPlugin {
      name = "json-path-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/json-path-api/2.9.0-58.v62e3e85b_a_655/json-path-api.hpi";
        sha256 = "268505aad59cb0d92ff4ca1f567556c523519b5217ca3e4591e1d4cc9b2646f5";
        };
      };
    junit = mkJenkinsPlugin {
      name = "junit";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/junit/1265.v65b_14fa_f12f0/junit.hpi";
        sha256 = "9a905ede679759291c6278a2f0fda558f67ca717f495d6d867277d0f9fd8916f";
        };
      };
    mailer = mkJenkinsPlugin {
      name = "mailer";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/mailer/472.vf7c289a_4b_420/mailer.hpi";
        sha256 = "c235d59ce7c422977ce31561b32a80232f707b2b3595a7b0a86d4d9220c18775";
        };
      };
    mapdb-api = mkJenkinsPlugin {
      name = "mapdb-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/mapdb-api/1.0.9-40.v58107308b_7a_7/mapdb-api.hpi";
        sha256 = "0dfd7a97d4a3436a740c82195dcdf2e102a5f0d7845db49b525a2c85f065663a";
        };
      };
    matrix-project = mkJenkinsPlugin {
      name = "matrix-project";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/matrix-project/822.824.v14451b_c0fd42/matrix-project.hpi";
        sha256 = "8a86b88fa86491307df663aacf9a0f150a4c5b55a619c6d4a83d5b44672938f7";
        };
      };
    maven-plugin = mkJenkinsPlugin {
      name = "maven-plugin";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/maven-plugin/3.23/maven-plugin.hpi";
        sha256 = "f412f9701aafa46d8e68dccb046b41745f2116ad91b76b0f35a24f21830097eb";
        };
      };
    metrics = mkJenkinsPlugin {
      name = "metrics";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/metrics/4.2.21-449.v6960d7c54c69/metrics.hpi";
        sha256 = "296a4179040f0bf9390e6fdebef0c2dbb42083ab029a7b7f71698a90b7bb99e0";
        };
      };
    mina-sshd-api-common = mkJenkinsPlugin {
      name = "mina-sshd-api-common";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/mina-sshd-api-common/2.12.1-101.v85b_e08b_780dd/mina-sshd-api-common.hpi";
        sha256 = "f3230889596334f3e812786aa05de42fdff470be258ff25fd088f22eb2da6e37";
        };
      };
    mina-sshd-api-core = mkJenkinsPlugin {
      name = "mina-sshd-api-core";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/mina-sshd-api-core/2.12.1-101.v85b_e08b_780dd/mina-sshd-api-core.hpi";
        sha256 = "97ea5d36db2c2165b4568cea0c2fc5489225504c601533179bc0f9fa10609375";
        };
      };
    node-iterator-api = mkJenkinsPlugin {
      name = "node-iterator-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/node-iterator-api/55.v3b_77d4032326/node-iterator-api.hpi";
        sha256 = "c9b2d8c7df2091a191f5562a35454ddc2343cfe9c274b1f6b5a83980f52b422f";
        };
      };
    oidc-provider = mkJenkinsPlugin {
      name = "oidc-provider";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/oidc-provider/62.vd67c19f76766/oidc-provider.hpi";
        sha256 = "1502ef4849136283eae0e7ac72f8ceb0e6f9c4b89363429ffc8f918ea779d514";
        };
      };
    parameterized-trigger = mkJenkinsPlugin {
      name = "parameterized-trigger";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/parameterized-trigger/787.v665fcf2a_830b_/parameterized-trigger.hpi";
        sha256 = "24cb0e52703f0a7df51e19fad5163fb39af3ab8dd7f2f05238c69824ddc0867c";
        };
      };
    pipeline-build-step = mkJenkinsPlugin {
      name = "pipeline-build-step";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-build-step/540.vb_e8849e1a_b_d8/pipeline-build-step.hpi";
        sha256 = "0a777f9282c726f5d254781eaacbdf2ceb813429b3d7ea54e0e739847f014b5a";
        };
      };
    pipeline-groovy-lib = mkJenkinsPlugin {
      name = "pipeline-groovy-lib";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-groovy-lib/704.vc58b_8890a_384/pipeline-groovy-lib.hpi";
        sha256 = "654825dc6b822c0c1948ee1a43675243b96ff30c0b08f13ac54295dead1d5437";
        };
      };
    pipeline-input-step = mkJenkinsPlugin {
      name = "pipeline-input-step";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-input-step/495.ve9c153f6067b_/pipeline-input-step.hpi";
        sha256 = "b1634db132b878b6cd49cd0da13ed590585fea3601c707931e3a7bf120859930";
        };
      };
    pipeline-milestone-step = mkJenkinsPlugin {
      name = "pipeline-milestone-step";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-milestone-step/119.vdfdc43fc3b_9a_/pipeline-milestone-step.hpi";
        sha256 = "0686e6f1b11bdd034cb1adbcbe6ecb65551c1f0e1cc4391066cde0d35197c7ec";
        };
      };
    pipeline-model-api = mkJenkinsPlugin {
      name = "pipeline-model-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-model-api/2.2198.v41dd8ef6dd56/pipeline-model-api.hpi";
        sha256 = "9c1051bb8021690de08ac67ac2046120bce989198432b86cc32d3a2c994913ab";
        };
      };
    pipeline-model-definition = mkJenkinsPlugin {
      name = "pipeline-model-definition";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-model-definition/2.2198.v41dd8ef6dd56/pipeline-model-definition.hpi";
        sha256 = "7ad6d8bba36481c377f6375c69862f0a815add4a0a9c0a30cd93d0b3c86fde81";
        };
      };
    pipeline-model-extensions = mkJenkinsPlugin {
      name = "pipeline-model-extensions";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-model-extensions/2.2198.v41dd8ef6dd56/pipeline-model-extensions.hpi";
        sha256 = "acd718bcca0fbf426e4ecefc52464903ff2d32578b372b267e6d3965b005fa40";
        };
      };
    pipeline-stage-step = mkJenkinsPlugin {
      name = "pipeline-stage-step";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-stage-step/312.v8cd10304c27a_/pipeline-stage-step.hpi";
        sha256 = "f254c8981de34c1a63f550c5ed374b885c25daf5df4d99555119a41b7a9f936c";
        };
      };
    pipeline-stage-tags-metadata = mkJenkinsPlugin {
      name = "pipeline-stage-tags-metadata";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/pipeline-stage-tags-metadata/2.2198.v41dd8ef6dd56/pipeline-stage-tags-metadata.hpi";
        sha256 = "5085a459d4814697075d9aa21af3a53879539d170e8a17e7f3cf463892d13601";
        };
      };
    plain-credentials = mkJenkinsPlugin {
      name = "plain-credentials";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/plain-credentials/179.vc5cb_98f6db_38/plain-credentials.hpi";
        sha256 = "1c467b5883f3a6c4a284dd1bc4e9edea535b1f23420b6b37709fe113c6e33efb";
        };
      };
    plugin-util-api = mkJenkinsPlugin {
      name = "plugin-util-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/plugin-util-api/4.1.0/plugin-util-api.hpi";
        sha256 = "5a9e24523080d294a3aed112cff24b8c24a09554b03a4199d58f82e550be84ff";
        };
      };
    prism-api = mkJenkinsPlugin {
      name = "prism-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/prism-api/1.29.0-13/prism-api.hpi";
        sha256 = "d9a4553b2e32e4344bcd97f7d87514a7f34fc06baad1f2027a1a81e0567a29bd";
        };
      };
    promoted-builds = mkJenkinsPlugin {
      name = "promoted-builds";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/promoted-builds/945.v597f5c6a_d3fd/promoted-builds.hpi";
        sha256 = "0f4fe74153f4f1884d2babf249a967a0d162d75dc0d462af260ff50e5b9509d8";
        };
      };
    rebuild = mkJenkinsPlugin {
      name = "rebuild";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/rebuild/332.va_1ee476d8f6d/rebuild.hpi";
        sha256 = "60eb87df685c714c89a8a7b6315a0332c2edcb19d149dd2099ed0cb25f55ba41";
        };
      };
    run-condition = mkJenkinsPlugin {
      name = "run-condition";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/run-condition/1.7/run-condition.hpi";
        sha256 = "d8601f47c021f8c6b8275735f5c023fec57b65189028e21abac91d42add0be42";
        };
      };
    scm-api = mkJenkinsPlugin {
      name = "scm-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/scm-api/690.vfc8b_54395023/scm-api.hpi";
        sha256 = "17da0081581b7a94e8cddcaa7d67d0149b2a0512dcf0e8f60c10a0b65fa2e0d7";
        };
      };
    script-security = mkJenkinsPlugin {
      name = "script-security";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/script-security/1335.vf07d9ce377a_e/script-security.hpi";
        sha256 = "efd2a522e9bb8cb2bd9136bb8015cdf13ac1676a961fb58c03418c93d99a60ee";
        };
      };
    snakeyaml-api = mkJenkinsPlugin {
      name = "snakeyaml-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/snakeyaml-api/2.2-111.vc6598e30cc65/snakeyaml-api.hpi";
        sha256 = "11013a4ab9f8c93420ba6ec85faab53759ea8afd53ba2db3f97c0ed4f0ebe82b";
        };
      };
    ssh-credentials = mkJenkinsPlugin {
      name = "ssh-credentials";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/ssh-credentials/337.v395d2403ccd4/ssh-credentials.hpi";
        sha256 = "9e52d9eca21790488ce4c4f296d023571eb8d35fd55faf1c0c490270399fbf22";
        };
      };
    ssh-slaves = mkJenkinsPlugin {
      name = "ssh-slaves";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/ssh-slaves/2.948.vb_8050d697fec/ssh-slaves.hpi";
        sha256 = "b5c14b5d4eadc28fa13c1f737f0b43d4a983c8b9e157f66f49c3c9ded93d7a66";
        };
      };
    structs = mkJenkinsPlugin {
      name = "structs";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/structs/337.v1b_04ea_4df7c8/structs.hpi";
        sha256 = "380f77f40d06174539410c04fcbc9ed12b7bd1f64775e58464233b489d6058ba";
        };
      };
    subversion = mkJenkinsPlugin {
      name = "subversion";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/subversion/1256.vee91953217b_6/subversion.hpi";
        sha256 = "4b0d17549b08bee880c821001e33311a9dcd6007961def031574a5d24155e4bb";
        };
      };
    support-core = mkJenkinsPlugin {
      name = "support-core";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/support-core/1427.v083f1d9372a_f/support-core.hpi";
        sha256 = "f2e04fb67ac8168b1e28cc9204df01b895fae0af7e2b8d1842f32a1a7537b453";
        };
      };
    token-macro = mkJenkinsPlugin {
      name = "token-macro";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/token-macro/400.v35420b_922dcb_/token-macro.hpi";
        sha256 = "822726088a5893f248b7bba1aea92ef6df1534b64acc0a23e2fc976db33439c8";
        };
      };
    trilead-api = mkJenkinsPlugin {
      name = "trilead-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/trilead-api/2.142.v748523a_76693/trilead-api.hpi";
        sha256 = "b75f84cf11ac2769bf150a99076370d0c2fd92e2e63f4e1d04aed504002621fe";
        };
      };
    variant = mkJenkinsPlugin {
      name = "variant";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/variant/60.v7290fc0eb_b_cd/variant.hpi";
        sha256 = "acbf1aebb9607efe0518b33c9dde9bd50c03d6a1a0fa62255865f3cf941fa458";
        };
      };
    vsphere-cloud = mkJenkinsPlugin {
      name = "vsphere-cloud";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/vsphere-cloud/2.27/vsphere-cloud.hpi";
        sha256 = "b584e8c515cdf41fa47740087677e11af80c402ef6c4fb5f153b9d8e05ccbdea";
        };
      };
    workflow-aggregator = mkJenkinsPlugin {
      name = "workflow-aggregator";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/workflow-aggregator/596.v8c21c963d92d/workflow-aggregator.hpi";
        sha256 = "45933e33058d48c6f3e70a37f31ecb65e48939ce91d46bc98b60f5595316c1d1";
        };
      };
    workflow-api = mkJenkinsPlugin {
      name = "workflow-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/workflow-api/1291.v51fd2a_625da_7/workflow-api.hpi";
        sha256 = "836d3ab116acb58fb75f295fb7f109674cfe9ad8d736f23fac94e6fc42f2f707";
        };
      };
    workflow-basic-steps = mkJenkinsPlugin {
      name = "workflow-basic-steps";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/workflow-basic-steps/1058.vcb_fc1e3a_21a_9/workflow-basic-steps.hpi";
        sha256 = "1d17becd03748cc6cce009cbba0ed35a28d17041f72c056b2eaa03615541374f";
        };
      };
    workflow-cps = mkJenkinsPlugin {
      name = "workflow-cps";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/workflow-cps/3894.vd0f0248b_a_fc4/workflow-cps.hpi";
        sha256 = "c05aa36720eef37c298681ca577fd578a12e4d71c503c9272c7c8c4d36c61697";
        };
      };
    workflow-durable-task-step = mkJenkinsPlugin {
      name = "workflow-durable-task-step";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/workflow-durable-task-step/1336.v768003e07199/workflow-durable-task-step.hpi";
        sha256 = "58abd099b81a71b052e3ead1ffb7d422575de2db196b62d4e7419cb01969bf7e";
        };
      };
    workflow-job = mkJenkinsPlugin {
      name = "workflow-job";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/workflow-job/1400.v7fd111b_ec82f/workflow-job.hpi";
        sha256 = "cad2dae02a386f98576e9f57f20c9040865e10177d6a5bce1b00e37dadce4324";
        };
      };
    workflow-multibranch = mkJenkinsPlugin {
      name = "workflow-multibranch";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/workflow-multibranch/783.va_6eb_ef636fb_d/workflow-multibranch.hpi";
        sha256 = "b0365b2a2286ad6c9f9fff160b9f736287f7549e19774c344d3ad0f9e74bb8ac";
        };
      };
    workflow-scm-step = mkJenkinsPlugin {
      name = "workflow-scm-step";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/workflow-scm-step/427.v4ca_6512e7df1/workflow-scm-step.hpi";
        sha256 = "4a06c4667e1bc437e89107abd9a316adaf51fca4fd504d12a525194777d34ad8";
        };
      };
    workflow-step-api = mkJenkinsPlugin {
      name = "workflow-step-api";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/workflow-step-api/657.v03b_e8115821b_/workflow-step-api.hpi";
        sha256 = "02f581bac28571aa1059fa18cd270b86e1dce8b1b28db3283686196d4e8e318a";
        };
      };
    workflow-support = mkJenkinsPlugin {
      name = "workflow-support";
      src = fetchurl {
        url = "https://updates.jenkins-ci.org/download/plugins/workflow-support/896.v175a_a_9c5b_78f/workflow-support.hpi";
        sha256 = "b6f47252ffbe39a73b6c6068541a9c506ce47dc0d4a1ca3ea2e6063934390793";
        };
      };
    }