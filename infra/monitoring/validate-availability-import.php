<?php
// Diagnostico offline: classes originais da imagem Zabbix fixada, sem DB ou sessao.
// Validacao de schema/gramatica NAO equivale a importar, vincular ou executar o host.
declare(strict_types=1);

$include = '/usr/share/zabbix/include/';
require_once $include.'defines.inc.php';
require_once $include.'gettextwrapper.inc.php';
require_once $include.'func.inc.php';

$classes = [];
$iterator = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($include.'classes', FilesystemIterator::SKIP_DOTS));
foreach ($iterator as $file) {
    if ($file->isFile() && $file->getExtension() === 'php') {
        $classes[$file->getBasename('.php')] = $file->getPathname();
    }
}
spl_autoload_register(static function (string $class) use ($classes): void {
    if (isset($classes[$class])) {
        require_once $classes[$class];
    }
});

$checks = 0;
function check(bool $condition, string $name): void {
    global $checks;
    if (!$condition) {
        throw new RuntimeException('check_failed: '.$name);
    }
    $checks++;
    echo json_encode(['check' => $name, 'result' => 'pass']).PHP_EOL;
}

try {
    $reader = new CJsonImportReader();
    $data = $reader->read(file_get_contents(__DIR__.'/availability-host.json'));
    $validator = new CXmlValidator(new CImportValidatorFactory(CXmlValidatorGeneral::JSON), CXmlValidatorGeneral::JSON);
    $validator->setStrict(true);
    $validated = $validator->validate($data, '/');
    check(isset($validated['zabbix_export']['hosts'][0]['httptests'][0]), 'original_zabbix_7_schema_accepts_host');

    foreach ($data['zabbix_export']['triggers'] as $index => $trigger) {
        $parser = new CExpressionParser();
        check($parser->parse($trigger['expression']) === CParser::PARSE_SUCCESS, 'trigger_grammar_'.$index);
    }

    $mutations = [
        'unsupported_export_version' => static function (array &$copy): void { $copy['zabbix_export']['version'] = '999.0'; },
        'unknown_step_field' => static function (array &$copy): void { $copy['zabbix_export']['hosts'][0]['httptests'][0]['steps'][0]['required_codes'] = '200'; },
        'invalid_redirect_enum' => static function (array &$copy): void { $copy['zabbix_export']['hosts'][0]['httptests'][0]['steps'][0]['follow_redirects'] = 'INVALID'; },
        'missing_host_name' => static function (array &$copy): void { unset($copy['zabbix_export']['hosts'][0]['host']); }
    ];
    foreach ($mutations as $name => $mutate) {
        $copy = $data;
        $mutate($copy);
        $rejected = false;
        try {
            $validator->validate($copy, '/');
        } catch (Exception $exception) {
            $rejected = true;
        }
        check($rejected, 'reject_'.$name);
    }
    echo json_encode(['checks' => $checks, 'result' => 'pass', 'scope' => 'offline_schema_and_grammar_only']).PHP_EOL;
} catch (Throwable $exception) {
    // Somente arquivo publico do repositorio entra neste processo; sem segredos.
    fwrite(STDERR, 'availability_import_validation_failed: '.$exception->getMessage().PHP_EOL);
    exit(1);
}
