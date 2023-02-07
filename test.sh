test="hello"
spawn_pod () {
    test="hi"
    echo $test
}

return_value=$(spawn_pod)
echo "this is return value $return_value"
